# encoding: utf-8

require 'github_flow/version'
require 'github_flow/configuration'
require 'github_flow/constants'
require 'github_flow/deprecation'

module GithubFlow
  extend Configuration

  class << self

    # Handle for the client instance
    attr_accessor :api_client

    # Alias for Github::Client.new
    #
    # @return [Github::Client]
    def new(options = {}, &block)
      @api_client = Github::Client.new(options, &block)
    end

    # Delegate to Github::Client
    #
    def method_missing(method, *args, &block)
      return super unless new.respond_to?(method)
      new.send(method, *args, &block)
    end

    def respond_to?(method, include_private = false)
      new.respond_to?(method, include_private) || super(method, include_private)
    end

  end

  module AutoloadHelper

    def autoload_all(prefix, options)
      options.each do |const_name, path|
        autoload const_name, File.join(prefix, path)
      end
    end

    def register_constant(options)
      options.each do |const_name, value|
        const_set const_name.upcase.to_s, value
      end
    end

    def lookup_constant(const_name)
      const_get const_name.upcase.to_s
    end

  end

  extend AutoloadHelper

  autoload_all 'github_flow',
    :Models => 'models',

end # GithubFlow
