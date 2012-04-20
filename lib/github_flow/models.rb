module GithubFlow
  module Models
    extend AutoloadHelper

    autoload_all 'github_flow/models',
      :Schema             => 'schema',
      :GithubRepo         => 'github_repo',
      :GithubRepoBranch   => 'github_repo_branch'
  end # Models
end # GithubFlow
