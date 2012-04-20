module GithubFlow
  module Models
    require 'active_record'

    class GithubRepo < ActiveRecord::Base
      self.table_name = 'github_repo'

      has_many :branches, :class_name => 'GithubRepoBranch'

      def repo_path
        "#{self.user}/#{self.repo}"
      end

      def to_s
        "<GithubRepo:#{repo_path}:{#{branches}}>"
      end
    end # GithubRepo
  end # Models
end # GithubFlow

