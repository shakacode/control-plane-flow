# frozen_string_literal: true

module TerraformConfig
  # rubocop:disable Metrics/ClassLength
  class Secret < Base
    REQUIRED_DATA_KEYS = {
      "aws" => %i[secret_key access_key],
      "azure-connector" => %i[url code],
      "ecr" => %i[secret_key access_key repos],
      "keypair" => %i[secret_key],
      "nats-account" => %i[account_id private_key],
      "opaque" => %i[payload],
      "tls" => %i[key cert],
      "userpass" => %i[username password],
      "dictionary" => []
    }.freeze

    attr_reader :name, :type, :data, :description, :tags

    def initialize(name:, type:, data:, description: nil, tags: nil)
      super()

      @name = name
      @type = type
      @description = description
      @tags = tags
      @data = prepare_data(type: type, data: data)
    end

    def to_tf
      block :resource, :cpln_secret, name do
        argument :name, name
        argument :description, description, optional: true
        argument :tags, tags, optional: true

        secret_data
      end
    end

    private

    def prepare_data(type:, data:)
      return data unless data.is_a?(Hash)

      data.underscore_keys.symbolize_keys.tap do |prepared_data|
        validate_required_data_keys!(type: type, data: prepared_data)
      end
    end

    def validate_required_data_keys!(type:, data:)
      required = REQUIRED_DATA_KEYS[type]
      missing_keys = required - data.keys
      raise ArgumentError, "Missing required data keys for #{type}: #{missing_keys.join(', ')}" if missing_keys.any?
    end

    def secret_data
      case type
      when "azure-sdk", "dictionary", "docker", "gcp"
        argument type.underscore, data, optional: true
      when "azure-connector", "aws", "ecr", "keypair", "nats-account", "opaque", "tls", "userpass"
        send("#{type.underscore}_tf")
      else
        raise "Invalid secret type given - #{type}"
      end
    end

    def aws_tf
      block :aws do
        argument :secret_key, data.fetch(:secret_key)
        argument :access_key, data.fetch(:access_key)
        argument :role_arn, data.fetch(:role_arn, nil), optional: true
        argument :external_id, data.fetch(:external_id, nil), optional: true
      end
    end

    def azure_connector_tf
      block :azure_connector do
        argument :url, data.fetch(:url)
        argument :code, data.fetch(:code)
      end
    end

    def ecr_tf
      block :ecr do
        argument :secret_key, data.fetch(:secret_key)
        argument :access_key, data.fetch(:access_key)
        argument :repos, data.fetch(:repos)
        argument :role_arn, data.fetch(:role_arn, nil), optional: true
        argument :external_id, data.fetch(:external_id, nil), optional: true
      end
    end

    def keypair_tf
      block :keypair do
        argument :secret_key, data.fetch(:secret_key)
        argument :public_key, data.fetch(:public_key, nil), optional: true
        argument :passphrase, data.fetch(:passphrase, nil), optional: true
      end
    end

    def nats_account_tf
      block :nats_account do
        argument :account_id, data.fetch(:account_id)
        argument :private_key, data.fetch(:private_key)
      end
    end

    def opaque_tf
      block :opaque do
        argument :payload, data.fetch(:payload)
        argument :encoding, data.fetch(:encoding, nil), optional: true
      end
    end

    def tls_tf
      block :tls do
        argument :key, data.fetch(:key)
        argument :cert, data.fetch(:cert)
        argument :chain, data.fetch(:chain, nil), optional: true
      end
    end

    def userpass_tf
      block :userpass do
        argument :username, data.fetch(:username)
        argument :password, data.fetch(:password)
        argument :encoding, data.fetch(:encoding, nil), optional: true
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
