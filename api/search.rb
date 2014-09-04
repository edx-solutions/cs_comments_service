require 'new_relic/agent/method_tracer'

get "#{APIPREFIX}/search/threads" do
  local_params = params # Necessary for params to be available inside blocks
  local_params['exclude_groups'] = value_to_boolean(local_params['exclude_groups'])
  sort_criteria = get_sort_criteria(local_params)

  search_text = local_params["text"]
  if !search_text || !sort_criteria
    {}.to_json
  else
    page = (local_params["page"] || DEFAULT_PAGE).to_i
    per_page = (local_params["per_page"] || DEFAULT_PER_PAGE).to_i

    # Because threads and comments are currently separate unrelated documents in
    # Elasticsearch, we must first query for all matching documents, then
    # extract the set of thread ids, and then sort the threads by the specified
    # criteria and paginate. For performance reasons, we currently limit the
    # number of documents considered (ordered by update recency), which means
    # that matching threads can be missed if the search terms are very common.

    get_matching_thread_ids = lambda do |search_text|
      self.class.trace_execution_scoped(["Custom/get_search_threads/es_search"]) do
        search = Tire.search Content::ES_INDEX_NAME do
          query do
            match [:title, :body], search_text, :operator => "AND"
            filtered do
              filter :term, :commentable_id => local_params["commentable_id"] if local_params["commentable_id"]
              filter :terms, :commentable_id => local_params["commentable_ids"].split(",") if local_params["commentable_ids"]
              filter :term, :course_id => local_params["course_id"] if local_params["course_id"]
              group_ids = []
              group_ids << local_params["group_id"] if local_params["group_id"]
              group_ids.concat(local_params["group_ids"].split(",")) if local_params["group_ids"]
              if local_params['exclude_groups']
                filter :not, :exists => {:field => :group_id}
              elsif not group_ids.empty?

                filter :or, [
                  {:not => {:exists => {:field => :group_id}}},
                  {:terms => {:group_id => group_ids}}
                ]
              end
            end
          end
          sort do
            by "updated_at", "desc"
          end
          size CommentService.config["max_deep_search_comment_count"].to_i
        end
        thread_ids = Set.new
        search.results.each do |content|
          case content.type
          when "comment_thread"
            thread_ids.add(content.id)
          when "comment"
            thread_ids.add(content.comment_thread_id)
          end
        end
        thread_ids
      end
    end

    # Sadly, Elasticsearch does not have a facility for computing suggestions
    # with respect to a filter. It would be expensive to determine the best
    # suggestion with respect to our filter parameters, so we simply re-query
    # with the top suggestion. If that has no results, then we return no results
    # and no correction.
    thread_ids = get_matching_thread_ids.call(search_text)
    corrected_text = nil
    if thread_ids.empty?
      suggest = Tire.suggest Content::ES_INDEX_NAME do
        suggestion "" do
          text search_text
          phrase :_all
        end
      end
      corrected_text = suggest.results.texts.first
      thread_ids = get_matching_thread_ids.call(corrected_text) if corrected_text
      corrected_text = nil if thread_ids.empty?
    end

    results = nil
    self.class.trace_execution_scoped(["Custom/get_search_threads/mongo_sort_page"]) do
      results = CommentThread.
        where(:id.in => thread_ids.to_a).
        order_by(sort_criteria).
        page(page).
        per(per_page).
        to_a
    end
    total_results = thread_ids.size
    num_pages = (total_results + per_page - 1) / per_page

    if results.length == 0
      collection = []
    else
      pres_threads = ThreadListPresenter.new(
        results,
        local_params[:user_id] ? user : nil,
        local_params[:course_id] || results.first.course_id
      )
      collection = pres_threads.to_hash
    end

    json_output = nil
    self.class.trace_execution_scoped(['Custom/get_search_threads/json_serialize']) do
      json_output = {
        collection: collection,
        corrected_text: corrected_text,
        total_results: total_results,
        num_pages: num_pages,
        page: page,
      }.to_json
    end
    json_output
  end
end

get "#{APIPREFIX}/search/threads/more_like_this" do
  CommentThread.tire.search page: 1, per_page: 5, load: true do |search|
    search.query do |query|
      query.more_like_this params["text"], fields: ["title", "body"], min_doc_freq: 1, min_term_freq: 1
    end
  end.results.map(&:to_hash).to_json
end

get "#{APIPREFIX}/search/threads/recent_active" do

  return [].to_json if not params["course_id"]

  follower_id = params["follower_id"]
  from_time = {
    "today" => Date.today.to_time,
    "this_week" => Date.today.to_time - 1.weeks,
    "this_month" => Date.today.to_time - 1.months,
  }[params["from_time"] || "this_week"]

  query_params = {}
  query_params["course_id"] = params["course_id"] if params["course_id"]
  query_params["commentable_id"] = params["commentable_id"] if params["commentable_id"]

  comment_threads = if follower_id
    User.find(follower_id).subscribed_threads
  else
    CommentThread.all
  end

  comment_threads.where(query_params.merge(:last_activity_at => {:$gte => from_time})).order_by(:last_activity_at.desc).limit(5).to_a.map(&:to_hash).to_json
end
