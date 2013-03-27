class GitPushService
  attr_accessor :project, :user, :push_data

  # This method will be called after each git update
  # and only if the provided user and project is present in GitLab.
  #
  # All callbacks for post receive action should be placed here.
  #
  # Now this method do next:
  #  1. Ensure project satellite exists
  #  2. Update merge requests
  #  3. Execute project web hooks
  #  4. Execute project services
  #  5. Create Push Event
  #
  def execute(project, user, oldrev, newrev, ref)
    @project, @user = project, user

    # Collect data for this git push
    @push_data = post_receive_data(oldrev, newrev, ref)

    create_push_event

    project.ensure_satellite_exists
    project.discover_default_branch
    project.repository.expire_cache

    if push_to_branch?(ref, oldrev)
      project.update_merge_requests(oldrev, newrev, ref, @user)
      project.execute_hooks(@push_data.dup)
      project.execute_services(@push_data.dup)
    end
  end

  # This method provide a sample data
  # generated with post_receive_data method
  # for given project
  #
  def sample_data(project, user)
    @project, @user = project, user
    commits = project.repository.commits(project.default_branch, nil, 3)
    post_receive_data(commits.last.id, commits.first.id, "refs/heads/#{project.default_branch}")
  end

  protected

  def create_push_event
    Event.create(
      project: project,
      action: Event::PUSHED,
      data: push_data,
      author_id: push_data[:user_id]
    )
  end

  # Produce a hash of post-receive data
  #
  # data = {
  #   before: String,
  #   after: String,
  #   ref: String,
  #   user_id: String,
  #   user_name: String,
  #   repository: {
  #     name: String,
  #     url: String,
  #     description: String,
  #     homepage: String,
  #   },
  #   commits: Array,
  #   total_commits_count: Fixnum
  # }
  #
  def post_receive_data(oldrev, newrev, ref)
    push_commits = project.repository.commits_between(oldrev, newrev)

    # Total commits count
    push_commits_count = push_commits.size

    # Get latest 20 commits ASC
    push_commits_limited = push_commits.last(20)

    # Hash to be passed as post_receive_data
    data = {
      before: oldrev,
      after: newrev,
      ref: ref,
      user_id: user.id,
      user_name: user.name,
      repository: {
        name: project.name,
        url: project.url_to_repo,
        description: project.description,
        homepage: project.web_url,
      },
      commits: [],
      total_commits_count: push_commits_count
    }
    data[:created] = true if (oldrev == "0000000000000000000000000000000000000000")
    data[:deleted] = true if (newrev == "0000000000000000000000000000000000000000")
    data[:compare] = "#{project.web_url}/compare/#{oldrev}...#{newrev}" if (oldrev != "0000000000000000000000000000000000000000" and newrev != "0000000000000000000000000000000000000000")

    # For performance purposes maximum 20 latest commits
    # will be passed as post receive hook data.
    #
    push_commits_limited.each do |commit|
      cdata = {
        id: commit.id,
        message: commit.safe_message,
        modified: [],
        added: [],
        removed: [],
        timestamp: commit.date.xmlschema,
        url: "#{Gitlab.config.gitlab.url}/#{project.path_with_namespace}/commit/#{commit.id}",
        author: {
          name: commit.author_name,
          email: commit.author_email
        }
      }
      commit.quick_diffs.each do |diff|
        cdata[:added] << diff.b_path if diff.new_file
        cdata[:removed] << diff.b_path if diff.deleted_file
        cdata[:modified] << diff.b_path unless (diff.new_file or diff.deleted_file)
      end
      data[:commits] << cdata
    end

    data
  end

  def push_to_branch? ref, oldrev
    ref_parts = ref.split('/')

    # Return if this is not a push to a branch (e.g. new commits)
    !(ref_parts[1] !~ /heads/ || oldrev == "00000000000000000000000000000000")
  end
end
