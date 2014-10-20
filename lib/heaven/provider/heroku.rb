module Heaven
  # Top-level module for providers.
  module Provider
    # A heroku API client.
    module HerokuApiClient
      def http_options
        {
          :url     => "https://api.heroku.com",
          :headers => {
            "Accept"        => "application/vnd.heroku+json; version=3",
            "Content-Type"  => "application/json",
            "Authorization" => Base64.encode64(":#{ENV["HEROKU_API_KEY"]}")
          }
        }
      end

      def http
        @http ||= Faraday.new(http_options) do |faraday|
          faraday.request :url_encoded
          faraday.adapter Faraday.default_adapter
          faraday.response :logger unless %w{staging production}.include?(Rails.env)
        end
      end
    end

    # A heroku build object.
    class HerokuBuild
      include HerokuApiClient

      attr_accessor :id, :info, :name
      def initialize(name, id)
        @id   = id
        @name = name
        @info = info!
      end

      def info!
        response = http.get do |req|
          req.url "/apps/#{name}/builds/#{id}"
        end
        Rails.logger.info "#{response.status} response for Heroku build info for #{id}"
        @info = JSON.parse(response.body)
      end

      def output
        response = http.get do |req|
          req.url "/apps/#{name}/builds/#{id}/result"
        end
        Rails.logger.info "#{response.status} response for Heroku build output for #{id}"
        @output = JSON.parse(response.body)
      end

      def lines
        @lines ||= output["lines"]
      end

      def stdout
        lines.map do |line|
          line["line"] if line["stream"] == "STDOUT"
        end.join
      end

      def stderr
        lines.map do |line|
          line["line"] if line["stream"] == "STDERR"
        end.join
      end

      def refresh!
        Rails.logger.info "Refreshing build #{id}"
        info!
      end

      def completed?
        success? || failed?
      end

      def success?
        info["status"] == "succeeded"
      end

      def failed?
        info["status"] == "failed"
      end
    end

    # The heroku provider.
    class HerokuHeavenProvider < DefaultProvider
      include HerokuApiClient

      attr_accessor :build
      def initialize(guid, payload)
        super
        @name = "heroku"
      end

      def app_name
        return nil unless custom_payload_config

        app_key = "heroku_#{environment}_name"
        if custom_payload_config.key?(app_key)
          custom_payload_config[app_key]
        else
          puts "Specify a There is no heroku specific app #{app_key} for the environment #{environment}"
          custom_payload_config["heroku_name"]  # default app name
        end
      end

      def archive_link
        @archive_link ||= api.archive_link(name_with_owner, :ref => sha)
      end

      def execute
        response = build_request
        return unless response.success?
        body   = JSON.parse(response.body)
        @build = HerokuBuild.new(app_name, body["id"])

        status.output = "http://travis-deploy-logs-production.herokuapp.com/heroku/#{environment}/#{custom_payload_name}/#{build.id}"
        status.pending!

        until build.completed?
          sleep 5
          build.refresh!
        end
      end

      def notify
        status.output = "http://travis-deploy-logs-production.herokuapp.com/heroku/#{environment}/#{custom_payload_name}/#{build.id}"

        if build && build.success?
          status.success!
        else
          status.failure!
        end
      end

      def setup
        credentials.setup!
      end

      private

      def build_request
        http.post do |req|
          req.url "/apps/#{app_name}/builds"
          body = {
            :source_blob => {
              :url     => archive_link,
              :version => sha
            }
          }
          req.body = JSON.dump(body)
        end
      end
    end
  end
end
