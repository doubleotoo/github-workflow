
def in_master?(grit, commit)
  grit.git.branch({ :contains => commit.sha }).match(/\* master/)
end

# TODO: better way to check for merge commit?
def merge_commit?(commit)
  commit.message.match(/^Merge branch/)
end

# ignore_commit
#
#   Filter commits to identify ones that require code review.
#
#   +grit+
#   +commit+
#
#   Returns true if the commit should not be ignored. This does not imply
#   that the commit needs to be code reviewed.
#
def ignore_commit(grit, commit)
  ignore = false

  if in_master?(grit, commit)
    #
    # Skip: commit merged from origin/master.
    #
    GithubFlow.log "#{commit.sha} is already in origin/master."
    ignore = true
  elsif merge_commit?(commit)
    #
    # Skip: merge commits
    #
    # TODO: unreliable check for regex in commit message.
    #       Loophole scenario: user explicitly adds merge
    #       message to commit to bypass review.
    #
    GithubFlow.log "#{commit.sha} is a merge commit."
    ignore = true
  elsif commit.stats.files.empty?
    #
    # Skip: empty commit (no files modified)
    #
    GithubFlow.log "#{commit.sha} has no file modifications (empty commit)."
    ignore = true
  end

  return ignore
end

# get_modified_files
#
# +commits+
#
def get_modified_files(commits)
  commits.collect {|commit|
    commit.stats.files.collect {|filename, adds, deletes, total| filename}
  }.flatten.compact.uniq
end

## get_closest_file
#
# Find the closest +filename+ starting at +path+.
#
# Example::
#
#   Given this directory structure:
#
#     ROOT/
#       TARGET.txt
#      subdir1/
#        TARGET.txt
#      subdir2/
#
#   get_closest_file(.., 'TARGET.txt', 'subdir2') => ROOT/subdir1/TARGET.txt
#   get_closest_file(.., 'TARGET.txt', 'subdir2') => ROOT/TARGET.txt
#
# TODO: return hash { :path_string => '', :grit_tree => '' }
# TODO: raise error if not found (instead of returning nil)?
#
# Returns a hash:
#
#   {
#     :dirname => "relative/path/to/dir",
#     :tree => :+Grit::Tree+
#   }
#
def get_closest_file(commit, filename, path)
  dirs = File.dirname(path).split(File::SEPARATOR)

  while not dirs.empty?
    currentpath = dirs.join(File::SEPARATOR)

    GithubFlow.log "Checking #{currentpath}/ for #{filename}"

    tree = commit.tree / currentpath / filename
    if tree.nil? # path/to/filename does not exist
      dirs.pop
    else
      return { :dirname => currentpath, :tree => tree }
    end
  end

  # Tree could be nil if no ROOT/filename exists.
  { :dirname => '', :tree => commit.tree / filename }
end # get_closest_file

# get_reviewers_for_file
#
def get_reviewers_for_file(commit, authors_file, file)
  reviewers = {}
  yamldata = nil

  GithubFlow.log "Locating closest file=#{authors_file} for #{commit.id_abbrev}:#{file}"
  grit_authors_file = get_closest_file(commit, authors_file, file)
  dirname = grit_authors_file[:dirname]
  tree = grit_authors_file[:tree]

  # Parse +authors_file+ (YAML) for +file+ code reviewers.
  if tree.nil?
    raise "The closest authors_file=#{authors_file} to file=#{file} is nil!"
  else
    GithubFlow.log "Located file=#{File.join(dirname, authors_file)} as the closest " +
                   "file=#{authors_file} for #{commit.id_abbrev}:#{file}"

    yaml = YAML.load(tree.data)
    reviewers = yaml['code-reviewers']
  end
end

# get_reviewers
#
# +grit+
# +authors_filename+ A YAML file.
# +commits+
#
# Get a list of code reviewers for a collection of commits,
# from the meta data in the HEAD of the repository.
#
# Returns a Hash:
#
#   {
#     :file => [reviewer1, reviewer2, ..],
#     ...
#   }
#
def get_reviewers_by_file(grit, authors_file, commits)
  files       = get_modified_files(commits)
  head_commit = grit.commits.first

  reviewers = {}
  files.each do |file|
    file_reviewers = get_reviewers_for_file(head_commit, authors_file, file)
    if file_reviewers.nil? or file_reviewers.empty?
      raise "file_reviewers=#{file_reviewers} (nil/empty) for file=#{file}"
    else
      GithubFlow.log "Code reviewers for #{head_commit.id_abbrev}:#{file}: #{file_reviewers}"
      reviewers[file] = file_reviewers
    end
  end

  GithubFlow.log "Code reviewers (by file) for commit=#{head_commit.id_abbrev}: #{reviewers}"
  reviewers
end # get_reviewers

def validate_reviewers(github, reviewers)
  reviewers.each do |reviewer|
    name = reviewer['name']
    github_user = reviewer['github-user']
    GithubFlow.log "Validating GitHub account \"#{github_user}\" for \"#{name}\""

    begin
      github.users.get_user(github_user)
    rescue Github::Error::NotFound
      raise InvalidGithubUser.new(github_user)
    end
  end
end # validate_reviewers

