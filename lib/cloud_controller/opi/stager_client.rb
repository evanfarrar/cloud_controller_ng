require 'httpclient'
require 'uri'
require 'cloud_controller/diego/staging_request'
require 'cloud_controller/opi/helpers'
require 'cloud_controller/opi/env_hash'
require 'cloud_controller/opi/base_client'

module OPI
  class StagerClient < BaseClient
    def stage(staging_guid, staging_details)
      logger.info('stage.request', staging_guid: staging_guid)

      if staging_details.lifecycle.type != VCAP::CloudController::Lifecycles::DOCKER && staging_details.lifecycle.type != VCAP::CloudController::Lifecycles::BUILDPACK
        raise("lifecycle type `#{staging_details.lifecycle.type}` is invalid")
      end

      request = to_request(staging_guid, staging_details)
      start_staging(staging_guid, request)
    end

    def stop_staging(staging_guid); end

    private

    class BuildpackLifecycle
      def initialize(action_builder, staging_guid, cc_uploader_url)
        @action_builder = action_builder
        @staging_guid = staging_guid
        @cc_uploader_url = cc_uploader_url
      end

      def to_hash
        lifecycle_data = @action_builder.lifecycle_data
        droplet_upload_uri = "#{@cc_uploader_url}/v1/droplet/#{@staging_guid}?cc-droplet-upload-uri=#{lifecycle_data[:droplet_upload_uri]}"
        {
          buildpack_lifecycle: {
              droplet_upload_uri: droplet_upload_uri,
              app_bits_download_uri: lifecycle_data[:app_bits_download_uri],
              buildpacks: lifecycle_data[:buildpacks]
          }
        }
      end
    end

    class DockerLifecycle
      def initialize(staging_details)
        @staging_details = staging_details
      end

      def to_hash
        {
          docker_lifecycle: {
            image: @staging_details.package.image,
            registry_username: @staging_details.package.docker_username,
            registry_password: @staging_details.package.docker_password
          }
        }
      end
    end

    def start_staging(staging_guid, staging_request)
      payload = MultiJson.dump(staging_request)
      response = client.post("/stage/#{staging_guid}", body: payload)
      if response.status_code != 202
        response_json = OPI.recursive_ostruct(JSON.parse(response.body))
        logger.info('stage.response', staging_guid: staging_guid, error: response_json.message)
        raise CloudController::Errors::ApiError.new_from_details('RunnerError', response_json.message)
      end
    end

    def to_request(staging_guid, staging_details)
      lifecycle_type = staging_details.lifecycle.type
      action_builder = VCAP::CloudController::Diego::LifecycleProtocol.protocol_for_type(lifecycle_type).staging_action_builder(config, staging_details)

      lifecycle = get_lifecycle(staging_details, staging_guid, action_builder)
      {
          app_guid: staging_details.package.app_guid,
          app_name: staging_details.package.app.name,
          staging_guid: staging_guid,
          org_name: staging_details.package.app.organization.name,
          org_guid: staging_details.package.app.organization.guid,
          space_name: staging_details.package.app.space.name,
          space_guid: staging_details.package.app.space.guid,
          environment: build_env(staging_details.environment_variables) + action_builder.task_environment_variables.to_a,
          completion_callback: staging_completion_callback(staging_details),
          lifecycle: lifecycle,
          cpu_weight: VCAP::CloudController::Diego::STAGING_TASK_CPU_WEIGHT,
          disk_mb: staging_details.staging_disk_in_mb,
          memory_mb: staging_details.staging_memory_in_mb
      }
    end

    def get_lifecycle(staging_details, staging_guid, action_builder)
      if staging_details.lifecycle.type == VCAP::CloudController::Lifecycles::DOCKER
        DockerLifecycle.new(staging_details)
      else
        cc_uploader_url = config.get(:opi, :cc_uploader_url)
        BuildpackLifecycle.new(action_builder, staging_guid, cc_uploader_url)
      end
    end

    def staging_completion_callback(staging_details)
      port   = config.get(:tls_port)
      scheme = 'https'

      auth      = "#{config.get(:internal_api, :auth_user)}:#{CGI.escape(config.get(:internal_api, :auth_password))}"
      host_port = "#{config.get(:internal_service_hostname)}:#{port}"
      path      = "/internal/v3/staging/#{staging_details.staging_guid}/build_completed?start=#{staging_details.start_after_staging}"
      "#{scheme}://#{auth}@#{host_port}#{path}"
    end

    def build_env(environment)
      env = OPI::EnvHash.muse(environment)
      env.map { |i| ::Diego::Bbs::Models::EnvironmentVariable.new(name: i['name'], value: i['value']) }
    end

    def logger
      @logger ||= Steno.logger('cc.bbs.stager_client')
    end
  end
end
