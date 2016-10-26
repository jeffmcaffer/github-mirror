require 'ghtorrent/transacted_gh_torrent'

class FilteredTransactedGHTorrent < TransactedGHTorrent

  def initialize(settings)
    super
    @org_filter = load_orgs_file(config(:mirror_orgs_file))
  end

  def ensure_repo(organization, repo, recursive = false)
    super if include_org? organization
  end

  def ensure_org(organization, members = true)
    super if include_org? organization
  end

  def ensure_repo_recursive(organization, repo)
    super if include_org? organization
  end

  private

  def include_org? (org)
    org = org.downcase
    # if it has been a while, reload the orgs list to detect orgs being added/removed
    if Time.now.to_ms > @next_check_time
      @org_filter = load_orgs_file config(:mirror_orgs_file)
    end
    result = @org_filter.include?(org)
    # if we miss, reload the orgs list in case an org was just added
    # TODO this may be a bit of overkill to actually reload. Perhaps a timestamp check?
    unless result
      @org_filter = load_orgs_file config(:mirror_orgs_file)
      result = @org_filter.include?(org)
    end

    warn "Organization #{org} excluded by filter" unless result
    result
  end

  def load_orgs_file(path)
    result = Set.new
    return result unless File.exists?(path)

    IO.foreach(path) do |x|
      x = x.strip
      result.add(x) unless x.empty?
    end
    @next_check_time = Time.now.to_ms + (5 * 60 * 1000)
    result
  end
end
