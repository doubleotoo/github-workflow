module GithubFlow
  module Models
    require 'active_record'

    class GithubRepo < ActiveRecord::Base
      self.table_name = 'github_repo'

      has_many :branches, :class_name => 'GithubRepoBranch'

      def path
        "#{self.user}/#{self.name}"
      end

      def to_s
        "<GithubRepo:#{path}:{#{branches}}>"
      end
    end # GithubRepo
  end # Models
end # GithubFlow

