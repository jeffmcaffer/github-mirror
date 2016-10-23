require 'ghtorrent/transacted_gh_torrent'

class FilteredTransactedGHTorrent < TransactedGHTorrent
  attr_reader :org_filter

  def initialize(settings)
    super
    @org_filter = load_orgs_file(config(:mirror_orgs_file))
    @next_check_time = 0
  end

  def ensure_repo(owner, repo, recursive = false)
    super if include_org? owner
  end

  def ensure_org(organization, members = true)
    super if include_org? owner
  end

  def ensure_repo_recursive(owner, repo)
    super if include_org? organization
  end

  private

  def include_org? (org)
    if Time.now.to_ms > next_check_time
      load_orgs_file config(:mirror_orgs_file)
    end
    result = org_filter.include?(org)
    warn "Organization #{org} excluded by filter" unless result
    result
  end

  def load_orgs_file(path)
    result = Set.new
    return result unless File.exists?(path)

    IO.foreach(path) do |x|
      x = x.strip
      if x.empty? == false
        result.add(x)
      end
    end
    next_check_time = Time.now.to_ms + (5 * 60 * 1000)
    result
  end
end
