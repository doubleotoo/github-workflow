# TODO: validate repo exists first

require 'github_flow'
require 'github_api'

require 'grit'
require 'tmpdir'

#GithubFlow::Models::Schema.new(adapter='sqlite3', database='tmp-demo.sqlite3', force=true)
#GithubFlow::Models::Schema.new
#GithubFlow::Models::Schema.new(adapter='sqlite3', database=':memory:', force=true, logger=nil)
GithubFlow::Models::Schema.new(adapter='sqlite3', database='tmp.sqlite3', force=true, logger=nil)

# repo = GithubFlow::Models::GithubRepo.create(:name => 'foo', :user => 'rose-compiler')
#if repo.valid?
#  puts 'Valid!'
#else
#  raise "Error: #{repo.errors.full_messages}"
#end

def pull_requests
  GithubFlow::Models::GithubRepo.all.each do |repo|
    page_no=1; @github.pull_requests.pull_requests(
      repo.user, repo.repo, {:state => 'open'}).each_page do |page|
        puts "Page #{page_no}"
        page.each do |pull_request|
          puts "#{pull_request.number} #{pull_request.state} #{pull_request.title}: #{pull_request.updated_at}"
          puts @github.pull_requests.comments 'doubleotoo', 'foo', pull_request.number
        end # page.each
      page_no += 1
    end # pull_requests.each_page
  end # GithubRepo.all
end # pull_requests

# puts Github::Repos.actions

# get_updated_branches
#
#   Polls GitHub repositories for new/updated branches (these are persisted).
#
#   +github+ is a +Github+ object (default='Github.new')
#
#   options::
#
#     :repos is an array of source GithubRepo objects.
#
#   Returns {
#     Github::Repos => [GithubRepoBranch, ...],
#     ...
#   }.
#
def get_updated_branches(github = Github.new, user_options = {}, &block)
  options = {
    :repos => GithubFlow::Models::GithubRepo.all
  }.merge(user_options).freeze
  #-----------------------------------------------------------------------------
  updated_repos = {} # { repo => [branch, ...] }

  options[:repos].compact.each do |repo|
    github.repos.branches(repo.user, repo.name).each_page do |page|
      page.each do |remote_branch|

        begin

          db_branch = repo.branches.find_by_name!(remote_branch.name)
          #puts "Branch already exists: #{db_branch}"

          #---------------------------------------------------------------------
          # Updated branch
          if db_branch.sha != remote_branch.commit.sha
            #puts "Branch updating: #{db_branch}"

            db_branch.sha = remote_branch.commit.sha
            db_branch.save

            if db_branch.valid?
              #puts "Branch updated: #{db_branch}"
              updated_repos[repo] ||= []
              updated_repos[repo] << db_branch
            else
              raise "Error: #{db_branch.errors.full_messages}"
            end
          end

        rescue ActiveRecord::RecordNotFound

          #---------------------------------------------------------------------
          # New branch
          db_branch = repo.branches.create(
            :name => remote_branch.name,
            :sha => remote_branch.commit.sha
          )

          if db_branch.valid?
            #puts "Branch is NEW: #{db_branch}"
            updated_repos[repo] ||= []
            updated_repos[repo] << db_branch
          else
            raise "Error: #{db_branch.errors.full_messages}"
          end

        end # begin..rescue
      end # page.each |remote_branch|
    end # list_branches.each_page
  end

  if block_given?
    yield updated_repos 
  end

  updated_repos
end # get_updated_branches

# get_commit
#
#   +github+ is a +Github+ object (default='Github.new')
#
#   options::
#
#     :user is a GitHub username (string)
#     :repo is a GitHub repository name (string)
#     :sha is a Git Sha1 (string)
#
def get_commit(github = Github.new, user_options = {}, &block)
  options = {}.merge(user_options).freeze
  raise 'Missing required option :user' if not options.has_key?(:user)
  raise 'Missing required option :repo' if not options.has_key?(:repo)
  raise 'Missing required option :sha' if not options.has_key?(:sha)
  #-----------------------------------------------------------------------------
  if github.repos.get_repo(options[:user], options[:repo]).nil?
    raise "repository #{options[:user]}/#{options[:repo]} does not exist."
  else
    commit = nil

    puts "Searching #{options[:user]}/#{options[:repo]} for #{options[:sha]}"

    # TODO: GitHub APIv3 bug? returns commit if it exists in a forked repo...
    # TODO: sent email to github support
    #commit = github.repos.commit(options[:user], options[:repo], options[:sha])

    # TODO: cloning the entire repository each time is slow...
    Dir.mktmpdir do |tmp_git_path|
      git = Grit::Git.new(tmp_git_path)
      git.clone({
            :quiet    => false,
            :verbose  => true,
            :progress => true,
            :branch   => 'master'
          },
          "http://github.com/#{options[:user]}/#{options[:repo]}.git",
          tmp_git_path)

      grit = Grit::Repo.new(tmp_git_path)
      if grit.git.branch( {:contains => options[:sha]} ).empty?
        commit = nil
      else
        commit = github.repos.commit(options[:user], options[:repo], options[:sha])
      end
    end

    if block_given?
      yield commit
    end
    return commit
  end
end # get_commit

#-------------------------------------------------------------------------------
# Main

# get_updated_branches_relative_to_repo
#
#   Polls GitHub repositories for new/updated branches that have new commits.
#   (Branches are persisted.)
#
#   +github+ is a +Github+ object (default='Github.new')
#
#   options::
#
#     :target_user is a GitHub username (string)
#     :target_repo is a GitHub repository name to check commits against.
#     :repos is an array of source GithubRepo objects.
#
#   Returns {
#     Github::Repos => [GithubRepoBranch, ...],
#     ...
#   }.
#
def get_updated_branches_relative_to_repo(github = Github.new, user_options = {}, &block)
  options = {
    :repos => GithubFlow::Models::GithubRepo.all
  }.merge(user_options).freeze
  raise 'Missing required option :user' if not options.has_key?(:target_user)
  raise 'Missing required option :target_repo' if not options.has_key?(:target_repo)
  #-----------------------------------------------------------------------------
  updated_repo_branches = {} # { repo => [branch, ...] }

  get_updated_branches(github, options) do |repos|
    repos.each do |repo, db_branches|
      db_branches.each do |db_branch|
        if get_commit(github,
                      :user => options[:target_user],
                      :repo => options[:target_repo],
                      :sha => db_branch.sha).nil?
          # new commit not in :target_repo
          updated_repo_branches[repo] ||= []
          updated_repo_branches[repo] << db_branch
          puts "#{db_branch.sha} does NOT exist in #{options[:target_user]}/#{options[:target_repo]}"
        else
          # old commit already exists in repository
          puts "#{db_branch.sha} EXISTS in #{options[:target_user]}/#{options[:target_repo]}"
        end
      end
    end
  end

  updated_repo_branches
end # get_updated_branches_relative_to_repo

@github = Github.new
puts get_updated_branches_relative_to_repo(@github,
                                      :target_user => 'doubleotoo',
                                      :target_repo => 'foo')


# puts
# puts '-' * 80
# puts GithubFlow::Models::GithubRepo.all
# puts GithubFlow::Models::GithubRepoBranch.all

