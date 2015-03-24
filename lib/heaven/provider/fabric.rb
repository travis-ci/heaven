module Heaven
  # Top-level module for providers.
  module Provider
    # The fabric provider.
    class Fabric < DefaultProvider
      def initialize(guid, payload)
        super
        @name = "fabric"
      end

      def task
        deployment_data["task"] || "deploy"
      end

      def deploy_command_format
        ENV["DEPLOY_COMMAND_FORMAT"] || "fab -R %{environment} %{task}:branch_name=%{ref}"
      end

      def execute
        return execute_and_log(["/usr/bin/true"]) if Rails.env.test?

        unless File.exist?(checkout_directory)
          log "Cloning #{repository_url} into #{checkout_directory}"
          execute_and_log(["git", "clone", clone_url, checkout_directory])
        end

        Dir.chdir(checkout_directory) do
          log "Fetching the latest code"
          execute_and_log(%w{git fetch})
          execute_and_log(["git", "reset", "--hard", sha])
          deploy_string = deploy_command_format % {
            :environment => environment,
            :task => task,
            :ref => ref
          }

          log "Executing fabric: #{deploy_string}"
          execute_and_log([deploy_string])
        end
      end
    end
  end
end
