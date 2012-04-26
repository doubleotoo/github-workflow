# TODO: validate repo exists first
#
require 'grit'
require 'tmpdir'
require 'yaml'

require 'github_api'
require 'github_flow'

require 'utilities'

#GithubFlow::Models::Schema.new(adapter='sqlite3', database='tmp-demo.sqlite3', force=true)
#GithubFlow::Models::Schema.new
#GithubFlow::Models::Schema.new(adapter='sqlite3', database=':memory:', force=true, logger=nil)
GithubFlow::Models::Schema.new(adapter='sqlite3', database='tmp.sqlite3', force=true, logger=nil)

#repo = GithubFlow::Models::GithubRepo.create(:name => 'foo', :user => 'rose-compiler')
#if repo.valid?
#  puts 'Valid!'
#else
#  raise "Error: #{repo.errors.full_messages}"
#end
#
#

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
#     :repos is an array of source GithubFlow::Models::GithubRepo objects.
#
#   Returns {
#     Github::Repos => [ {:new => GithubRepoBranch, :old_sha => SHA1-string, ...],
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

            old_sha = db_branch.sha
            db_branch.sha = remote_branch.commit.sha
            db_branch.save

            if db_branch.valid?
              #puts "Branch updated: #{db_branch}"
              updated_repos[repo] ||= []
              updated_repos[repo] << {
                :new => db_branch,
                :old_sha => old_sha
              }
            else
              raise "Error: #{db_branch.errors.full_messages}"
            end
          else
            #puts "Branch is up-to-date: #{db_branch}!"
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
              updated_repos[repo] << {
                :new => db_branch,
                :old_sha => nil
              }
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

    GithubFlow.log "Searching #{options[:user]}/#{options[:repo]} for #{options[:sha]}"

    # TODO: GitHub APIv3 bug? returns commit if it exists in a forked repo...
    # TODO: sent email to github support
    #commit = github.repos.commit(options[:user], options[:repo], options[:sha])

    # TODO: cloning the entire repository each time is slow...
    # TODO: we may already have a clone of this repository...
    repo_path = "https://github.com/#{options[:user]}/#{options[:repo]}.git"

    GithubFlow.log "$ git clone #{repo_path}"

    Dir.mktmpdir do |tmp_git_path|
      git = Grit::Git.new(tmp_git_path)
      git.clone({
            :quiet    => false,
            :verbose  => true,
            :progress => true,
            :branch   => 'master'
          },
          repo_path,
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

# get_updated_branches_relative_to_repo
#
#   Polls GitHub repositories for new/updated branches that have new commits.
#   (Branches are persisted.)
#
#   +github+ is a +Github+ object (default='Github.new')
#
#   options::
#
#     :base_user is a GitHub username (string)
#     :base_repo is a GitHub repository name to check commits against.
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
  raise 'Missing required option :base_user' if not options.has_key?(:base_user)
  raise 'Missing required option :base_repo' if not options.has_key?(:base_repo)
  #-----------------------------------------------------------------------------
  updated_branches = {} # { repo => [branch, ...] }

  get_updated_branches(github, options) do |updated_repos|
    updated_repos.each do |updated_repo, updated_db_branches|
      updated_db_branches.each do |updated_db_branch_hash|
        updated_db_branch = updated_db_branch_hash[:new]
        old_sha = updated_db_branch_hash[:old_sha]
        if get_commit(github,
                      :user => options[:base_user],
                      :repo => options[:base_repo],
                      :sha => updated_db_branch.sha).nil?
          # new commit not in :base_repo
          updated_branches[updated_repo] ||= []
          updated_branches[updated_repo] << updated_db_branch_hash
          GithubFlow.log "#{updated_db_branch.sha} does NOT exist in #{options[:base_user]}/#{options[:base_repo]}"
        else
          # old commit already exists in repository
          GithubFlow.log"#{updated_db_branch.sha} EXISTS in #{options[:base_user]}/#{options[:base_repo]}"
        end
      end
    end
  end

  if block_given?
    yield updated_branches
  end
  updated_branches
end # get_updated_branches_relative_to_repo

# TODO: add labels 'pull-request', 'test-request'
def create_pull_requests_for_updated_branches(github = Github.new, user_options ={}, &block)
  options = {
    :repos => GithubFlow::Models::GithubRepo.all,
    :base_branch => 'master'
  }.merge(user_options).freeze
  raise 'Missing required option :base_user' if not options.has_key?(:base_user)
  raise 'Missing required option :base_repo' if not options.has_key?(:base_repo)
  #-----------------------------------------------------------------------------

  updated_repo_branches = get_updated_branches_relative_to_repo(github,
                                      :base_user => options[:base_user],
                                      :base_repo => options[:base_repo])
  updated_repo_branches.each do |updated_repo, updated_branches|
    updated_branches.each do |updated_branch_hash|
      updated_branch = updated_branch_hash[:new]
      old_sha = updated_branch_hash[:old_sha]

      # TODO: add ass method option
      next if not updated_branch.name.match(/-rc$/)

      GithubFlow.log 'Creating pull request: ' +
        "[from: #{updated_repo.path}:#{updated_branch.name} (#{updated_branch.sha})] " +
        "[into: #{options[:base_user]}/#{options[:base_repo]}:#{options[:base_branch]}]"

      # TODO: between [rose-compiler:rose, user:branch]
      file_reviewers = {}
      Dir.mktmpdir do |tmp_git_path|
        git = Grit::Git.new(tmp_git_path)
        git.clone({
              :quiet    => false,
              :verbose  => true,
              :progress => true,
              :branch   => 'master'
            },
            "http://github.com/#{updated_repo.path}.git",
            tmp_git_path)

        grit = Grit::Repo.new(tmp_git_path)
        new_commits = grit.commits_between('origin/master', updated_branch.sha)
        review_commits = new_commits.select { |commit| ignore_commit(grit, commit) == false }
        ignored_commits = new_commits - review_commits

        GithubFlow.log "New commits: #{new_commits.size} #{new_commits}"
        GithubFlow.log "Ignored commits: #{ignored_commits.size} #{ignored_commits}"

        file_reviewers = get_reviewers_by_file(grit, 'AUTHORS.yml', review_commits)

        # Only need to validate each unique user once.
        reviewers = []
        file_reviewers.each do |f, r|
          reviewers << r
        end
        reviewers = reviewers.flatten.compact.uniq

        validate_reviewers(github, reviewers)
      end # Dir.mktmpdir

      # Don't allow self-reviews. Someone else has to review your work!
      file_reviewers = file_reviewers.each do |file, reviewers|
        reviewers = reviewers.collect do |reviewer|
          if reviewer['github-user'] == updated_repo.user
            nil
          else
            reviewer
          end
        end.compact
        file_reviewers[file] = reviewers
      end

      GithubFlow.log "Reviewers for new pull request: #{file_reviewers}"

      #---------------------------------
      # Pull request description body
      #---------------------------------
      body = "(Automatically generated pull-request.)\n"
      file_reviewers.each {|file, reviewers|
        body << reviewers.collect {|r| "\n@#{r['github-user']} "}.join + ": please code review #{file}."
      }

      begin
        pull_request = github.pull_requests.create_request(
            options[:base_user],
            options[:base_repo],
            'title' => "Merge #{updated_repo.user}:#{updated_branch.name} (#{updated_branch.sha[0,8]})",
            'body'  => body,
            'head'  => "#{updated_repo.user}:#{updated_branch.sha}",
            'base'  => "#{options[:base_branch]}")
        GithubFlow.log "Created GitHub::PullRequest: #{pull_request.to_json}"

        updated_repo.pull_requests.create!(
          :issue_number => pull_request.number,
          :base_github_repo_path => "#{options[:base_user]}/#{options[:base_repo]}",
          :base_sha => options[:base_branch],
          :head_sha => updated_branch.sha)
        GithubFlow.log 'Persisted GitHubFlow::PullRequest'
      rescue Github::Error::UnprocessableEntity
        # TODO: existing pull request
        # TODO: ...check if it's being tested already. If so, create a new request.
        # TODO: should have been caught above
        # e = GithubFlow::Error::PullRequestExistsError.new($!.response_message)
        # if e.matches?
        #   raise e
        # else
        #   raise "Unknown Github::Error: #{$!}"
        # end
        GithubFlow.log "Github Error"
      end # begin..rescue

      #-------------------------------------------------------------------------
      # Update pull request
      #
      # (This extra step is simply a convenience for code reviewers.)
      #
      # Update the pull request's description with links to each file's diff-url.
      # This allows a code-reviewer to simply click the link to jump to the diff.
      #
      # Example::
      #
      #   Markdown:
      #     @doubleotoo: please code review \
      #     [src/README](https://github.com/doubleotoo/foo/pull/40/files#diff-0).
      #
      #   Visible HTML:
      #     @doubleotoo: please code review src/README.
      #
      #
      # First, we compute the "diff number" (i.e. ../files#diff-<number>) for
      # each file.
      #
      #   Note: This is currently quite hackish. There's no json API that maps
      #   a file to a diff number. So our best bet is to grab the array of
      #   pull_request files and then hope that a file's index in the array is
      #   it's diff number.
      #     I suppose we could just link to the diff page instead...
      #
      #
      # If this update step fails, the pull_request will have a description,
      # requesting developers to code review files--there just won't be any
      # nice HTML links to the diff page.
      #
      #-------------------------------------------------------------------------
      pull_request_file_diff_number = {}
      i=0; github.pull_requests.files(options[:base_user],
                                      options[:base_repo],
                                      pull_request.number).each_page do |page|
          page.each do |file|
            pull_request_file_diff_number[file.filename] = i
            i += 1
          end
        end

      #---------------------------------
      # Pull request description body
      #
      #   + With diff-links for files
      #---------------------------------
      body = "(Automatically generated pull-request.)\n"
      file_reviewers.each {|file, reviewers|
        diff_number = pull_request_file_diff_number[file]
        diff_url = "#{pull_request.html_url}/files#diff-#{diff_number}"
        diff_link = "[#{file}](#{diff_url})" # markdown [name](anchor)
        GithubFlow.log "diff_link='#{diff_link}' for #{file}"
        body << reviewers.collect {|r| "\n@#{r['github-user']} "}.join + ": please code review #{diff_link}."

        raise "diff_number is nil for #{file}!" if diff_number.nil?
      }

      github.pull_requests.update_request(options[:base_user],
                                          options[:base_repo],
                                          pull_request.number,
                                          'body' => body)
      GithubFlow.log "Updated GitHub::PullRequest with diff-links for files: #{pull_request.to_json}"
    end # updated_branches.each
  end # updated_repo_branches.each
end # create_pull_requests_for_updated_branches

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

begin
  GithubFlow.debug = true
  #Grit.debug = true

  @github = Github.new(:basic_auth => 'doubleotoo:x')

  create_pull_requests_for_updated_branches(
      @github,
      :base_user => 'doubleotoo',
      :base_repo => 'foo',
      :base_branch => 'master')
  exit 0

  # puts GitPulls.start('list')
  pulls = @github.pull_requests.requests('doubleotoo', 'foo')
  pulls.reverse.each do |p|
    puts "Number : #{p.number}"
    puts "Label : #{p.head}"
    puts "Created : #{p.created_at}"
    puts "Votes : #{p.votes}"
    puts "Comments : #{p.comments}"
    puts
    puts "Title : #{p.title}"
    puts "Body :"
    puts
    puts p.body
    puts
    puts '------------'
    @github.issues.comments('doubleotoo', 'foo', p.number).each_page do |page|
      page.each do |c|
        puts "ID : #{c.id}"
        puts "Author: #{c.user.login}"
        puts "Created : #{c.created_at}"
        puts
        puts "Body :"
        puts
        puts c.body
        puts
        puts '------------'
      end
    end
    puts
  end

rescue Github::Error::GithubError
  puts "Github API error response message:\n#{$!.response_message}"
end

