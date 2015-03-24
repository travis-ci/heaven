web: bundle exec unicorn -p $PORT -c config/unicorn.rb
deployments: bundle exec rake resque:work QUEUE=deployments,locks
statuses: bundle exec rake resque:work QUEUE=deployment_statuses,events,statuses
