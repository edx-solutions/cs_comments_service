source 'https://rubygems.org'
ruby "2.3.7"

gem 'pry'
gem 'pry-nav'

# Use with command-line debugging, but not RubyMine
#gem 'debugger'

gem 'bundler'

gem 'rake', '~> 10.4', '>= 10.4.2'

gem 'sinatra', '~> 1.4', '>= 1.4.8'
gem 'sinatra-param', '~> 1.4'

gem 'yajl-ruby'
gem 'mongo', '~> 2.3', '= 2.3.1'
gem 'activemodel', '~> 4.2', '= 4.2.8'
gem 'mongoid', '~> 5.1', '= 5.1.6'
gem 'bson', '~> 4.3'
gem 'protected_attributes'

gem 'delayed_job'
gem 'delayed_job_mongoid'

gem "enumerize"

# MongoID version is updated to 5.4, for that we have to use latest dependency gems
# so commented below two gems and used their dependent versions.
# FIXME: We should remove these commented gems after successful deployment
#gem 'mongoid-tree', :git => 'https://github.com/macdiesel/mongoid-tree'
#gem 'rs_voteable_mongo', :git => 'https://github.com/navneet35371/voteable_mongo.git'
gem 'mongoid-tree'
gem 'rs_voteable_mongo', '~> 1.1'

gem 'mongoid_magic_counter_cache'

gem 'will_paginate_mongoid', "~>2.0"
gem 'rdiscount'
gem 'nokogiri', "~>1.6.8"

gem 'elasticsearch', '~> 1.1.2'
gem 'elasticsearch-model', '~> 0.1.9'

gem 'dalli'

gem 'rest-client'

group :test do
  gem 'codecov', :require => false
  gem 'mongoid_cleaner', '~> 1.2.0'
  gem 'factory_girl', '~> 4.0'
  gem 'faker', '~> 1.6'
  gem 'guard'
  gem 'guard-unicorn'
  gem 'rack-test', :require => 'rack/test'
  gem 'rspec', '~> 2.11.0'
  gem 'webmock', '~> 1.22'
end

# FIXME Remove version restriction once ruby upgraded to 2.x
gem 'newrelic_rpm', '~> 3.16.0'
gem 'unicorn'
gem 'rack-timeout', '= 0.4.2'
gem "i18n"
gem "rack-contrib", :git => 'https://github.com/rack/rack-contrib.git', :ref => '6ff3ca2b2d988911ca52a2712f6a7da5e064aa27'
