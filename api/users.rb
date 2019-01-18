require 'new_relic/agent/method_tracer'
require 'date'

post "#{APIPREFIX}/users" do
  user = User.new(external_id: params["id"])
  user.username = params["username"]
  user.save
  if user.errors.any?
    error 400, user.errors.full_messages.to_json
  else
    user.to_hash.to_json
  end
end

get "#{APIPREFIX}/users/:user_id" do |user_id|
  begin
    # Get any group_ids that may have been specified (will be an empty list if none specified).
    group_ids = get_group_ids_from_params(params)
    user.to_hash(complete: bool_complete, course_id: params["course_id"], group_ids: group_ids).to_json
  rescue Mongoid::Errors::DocumentNotFound
    error 404
  end
end

get "#{APIPREFIX}/users/:user_id/active_threads" do |user_id|
  return {}.to_json if not params["course_id"]

  page = (params["page"] || DEFAULT_PAGE).to_i
  per_page = (params["per_page"] || DEFAULT_PER_PAGE).to_i
  per_page = DEFAULT_PER_PAGE if per_page <= 0

  active_contents = Content.where(author_id: user_id, anonymous: false, anonymous_to_peers: false, course_id: params["course_id"])
                           .order_by(updated_at: :desc)

  # Get threads ordered by most recent activity, taking advantage of the fact
  # that active_contents is already sorted that way
  active_thread_ids = active_contents.inject([]) do |thread_ids, content|
    thread_id = content._type == "Comment" ? content.comment_thread_id : content.id
    thread_ids << thread_id if not thread_ids.include?(thread_id)
    thread_ids
  end

  threads = CommentThread.course_context.in({"_id" => active_thread_ids})

  group_ids = get_group_ids_from_params(params)
  if not group_ids.empty?
    threads = get_group_id_criteria(threads, group_ids)
  end

  num_pages = [1, (threads.count / per_page.to_f).ceil].max
  page = [num_pages, [1, page].max].min

  sorted_threads = threads.sort_by {|t| active_thread_ids.index(t.id)}
  paged_threads = sorted_threads[(page - 1) * per_page, per_page]

  presenter = ThreadListPresenter.new(paged_threads, user, params[:course_id])
  collection = presenter.to_hash

  json_output = nil
  json_output = {
  collection: collection,
  num_pages: num_pages,
  page: page,
  }.to_json
  json_output

end

put "#{APIPREFIX}/users/:user_id" do |user_id|
  user = User.find_or_create_by(external_id: user_id)
  user.update_attributes(params.slice(*%w[username default_sort_key]))
  if user.errors.any?
    error 400, user.errors.full_messages.to_json
  else
    user.to_hash.to_json
  end
end

post "#{APIPREFIX}/users/:user_id/read" do |user_id|
  user.mark_as_read(source)
  user.reload.to_hash.to_json
end

def _user_social_stats(user_id, params)
  begin
    return {}.to_json if not params["course_id"]

    # parse the optional "end" date filter passed in by the caller
    end_date = DateTime.iso8601(params["end_date"]) if params["end_date"]
    thread_type = params["thread_type"]

    course_id = params["course_id"]
    thread_ids_filter = params["thread_ids"].split(",") if params["thread_ids"]

    user_stats = {}
    thread_ids = {}
    flat_thread_ids = []

    content_selector = {course_id: course_id, anonymous: false, anonymous_to_peers: false}
    if end_date
      content_selector[:created_at.lte] = end_date
    end

    def set_template_result(user_id, user_stats, thread_ids)
      user_stats[user_id] = {
        "num_threads" => 0,
        "num_comments" => 0,
        "num_replies" => 0,
        "num_upvotes" => 0,
        "num_downvotes" => 0,
        "num_flagged" => 0,
        "num_comments_generated" => 0,
        "num_thread_followers" => 0,
        "num_threads_read" => 0,
      }
      thread_ids[user_id] = []
    end

    if user_id != '*'
      content_selector["author_id"] = user_id
      set_template_result(user_id, user_stats, thread_ids)
    end

    # get all metadata regarding forum content, but don't bother to fetch the body
    # as we don't need it and we shouldn't push all that data over the wire
    content = Content.where(content_selector).without(:body)

    if thread_type || thread_ids_filter
      thread_selector = {course_id: course_id, anonymous: false, anonymous_to_peers: false}
      if end_date
        thread_selector[:created_at.lte] = end_date
      end
      if thread_type
        thread_selector["thread_type"] = thread_type
      end
      if thread_ids_filter
        thread_selector[:commentable_id.in] = thread_ids_filter
      end

      target_threads = CommentThread.where(thread_selector).only(:_id).map(&:_id)
      content = content.select do |c|
        (c._type == "CommentThread" && c.thread_type == thread_type) || target_threads.include?(c.comment_thread_id)
      end
    end

    content.each do |item|
      user_id = item.author_id

      if user_stats.key?(user_id) == false then
        set_template_result(user_id, user_stats, thread_ids)
      end

      if item._type == "CommentThread" then
        user_stats[user_id]["num_threads"] += 1
        thread_ids[user_id].push(item._id)
        flat_thread_ids.push(item._id)
        user_stats[user_id]["num_comments_generated"] += item.comment_count
      elsif item._type == "Comment" and item.parent_ids == [] then
        user_stats[user_id]["num_comments"] += 1
      else
        user_stats[user_id]["num_replies"] += 1
      end

      # don't allow for self-voting
      item.votes["up"].delete(user_id)
      item.votes["down"].delete(user_id)

      user_stats[user_id]["num_upvotes"] += item.votes["up"].count
      user_stats[user_id]["num_downvotes"] += item.votes["down"].count

      user_stats[user_id]["num_flagged"] += item.abuse_flaggers.count

    end

    # with the array of objectId's for threads, get a count of number of other users who have a subscription on it
    user_stats.keys.each do |user_id|
      user_stats[user_id]["num_thread_followers"] = Subscription.where(:subscriber_id.ne => user_id, :source_id.in => thread_ids[user_id]).count()
    end

    # Get the number of threads read by each user.
    users = User.only([:_id, :read_states]).where("read_states.course_id" => course_id)
    users.each do |user|
      if user_stats.key?(user._id) == false then
        set_template_result(user._id, user_stats, thread_ids)
      end
      user_stats[user._id]["num_threads_read"] = user.read_states.find_by(:course_id => course_id).last_read_times.length
    end

    user_stats.to_json
  end
end

get "#{APIPREFIX}/users/:user_id/social_stats" do |user_id|
  _user_social_stats(user_id, params)
end

post "#{APIPREFIX}/users/:user_id/social_stats" do |user_id|
  _user_social_stats(user_id, params)
end

post "#{APIPREFIX}/users/:user_id/retire" do |user_id|
  if not params["retired_username"]
    error 500, {message: "Missing retired_username param."}.to_json
  end
  begin
    user = User.find_by(external_id: user_id)
  rescue Mongoid::Errors::DocumentNotFound
    error 404, {message: "User not found."}.to_json
  end
  user.update_attribute(:email, "")
  user.update_attribute(:notification_ids, [])
  user.update_attribute(:read_states, [])
  user.unsubscribe_all
  user.retire_all_comments(params["retired_username"])
  user.update_attribute(:username, params["retired_username"])
end
