"""
    FeedbackStats

Personal GitHub activity statistics and analysis.

Track your issues, PRs, comments, contributions, and watched repos
across all your repositories.

# Usage

```julia
using FeedbackStats

# Configure with your token
FeedbackStats.configure!(token=ENV["GITHUB_TOKEN"], username="hyperpolymath")

# Fetch your activity
activity = FeedbackStats.fetch_all_activity()

# Generate statistics
stats = FeedbackStats.compute_stats(activity)

# View summary
FeedbackStats.summary(stats)

# Export to CSV
FeedbackStats.export_csv(stats, "my_github_stats.csv")

# Generate plots
FeedbackStats.plot_contributions(stats)
```
"""
module FeedbackStats

using HTTP
using JSON3
using DataFrames
using CSV
using Dates
using Statistics
using StatsBase
using UnicodePlots

export configure!, fetch_all_activity, compute_stats, summary, export_csv
export plot_contributions, plot_issue_timeline, plot_response_times

# Configuration
const CONFIG = Ref{Dict{Symbol,Any}}(Dict{Symbol,Any}())

"""
    configure!(; token, username, api_url="https://api.github.com")

Configure the GitHub API connection.
"""
function configure!(; token::String, username::String, 
                    api_url::String="https://api.github.com")
    CONFIG[] = Dict(
        :token => token,
        :username => username,
        :api_url => api_url,
        :headers => [
            "Authorization" => "Bearer $token",
            "Accept" => "application/vnd.github+json",
            "X-GitHub-Api-Version" => "2022-11-28"
        ]
    )
end

# API Functions

function api_get(path::String; params::Dict=Dict())
    url = CONFIG[][:api_url] * path
    if !isempty(params)
        url *= "?" * join(["$k=$v" for (k,v) in params], "&")
    end
    
    response = HTTP.get(url, CONFIG[][:headers])
    JSON3.read(String(response.body))
end

function paginate_all(path::String; params::Dict=Dict())
    results = []
    page = 1
    per_page = 100
    
    while true
        page_params = merge(params, Dict("page" => page, "per_page" => per_page))
        items = api_get(path; params=page_params)
        
        if isempty(items)
            break
        end
        
        append!(results, items)
        
        if length(items) < per_page
            break
        end
        
        page += 1
    end
    
    results
end

# Data Fetching

"""
    fetch_my_issues()

Fetch all issues created by the configured user.
"""
function fetch_my_issues()
    username = CONFIG[][:username]
    items = paginate_all("/search/issues"; 
        params=Dict("q" => "author:$username type:issue"))
    
    DataFrame(
        id = [i.number for i in items],
        repo = [split(i.repository_url, "/")[end-1:end] |> x -> join(x, "/") for i in items],
        title = [i.title for i in items],
        state = [i.state for i in items],
        created_at = [DateTime(i.created_at[1:19]) for i in items],
        closed_at = [isnothing(i.closed_at) ? missing : DateTime(i.closed_at[1:19]) for i in items],
        comments = [i.comments for i in items],
        labels = [join([l.name for l in i.labels], ", ") for i in items]
    )
end

"""
    fetch_my_prs()

Fetch all PRs created by the configured user.
"""
function fetch_my_prs()
    username = CONFIG[][:username]
    items = paginate_all("/search/issues";
        params=Dict("q" => "author:$username type:pr"))
    
    DataFrame(
        id = [i.number for i in items],
        repo = [split(i.repository_url, "/")[end-1:end] |> x -> join(x, "/") for i in items],
        title = [i.title for i in items],
        state = [i.state for i in items],
        created_at = [DateTime(i.created_at[1:19]) for i in items],
        merged_at = [get(i, :merged_at, nothing) |> x -> isnothing(x) ? missing : DateTime(x[1:19]) for i in items],
        comments = [i.comments for i in items],
    )
end

"""
    fetch_my_comments()

Fetch recent comments made by the configured user.
"""
function fetch_my_comments()
    username = CONFIG[][:username]
    # Note: GitHub API doesn't have a direct endpoint for all user comments
    # We'd need to iterate through repos or use the events API
    # This is a simplified version using events
    
    events = api_get("/users/$username/events"; params=Dict("per_page" => 100))
    
    comments = filter(e -> e.type in ["IssueCommentEvent", "CommitCommentEvent", "PullRequestReviewCommentEvent"], events)
    
    DataFrame(
        type = [c.type for c in comments],
        repo = [c.repo.name for c in comments],
        created_at = [DateTime(c.created_at[1:19]) for c in comments],
    )
end

"""
    fetch_contributions()

Fetch contribution statistics.
"""
function fetch_contributions()
    username = CONFIG[][:username]
    
    # Get repos user has contributed to
    repos = paginate_all("/users/$username/repos"; params=Dict("type" => "all"))
    
    DataFrame(
        repo = [r.full_name for r in repos],
        stars = [r.stargazers_count for r in repos],
        forks = [r.forks_count for r in repos],
        open_issues = [r.open_issues_count for r in repos],
        created_at = [DateTime(r.created_at[1:19]) for r in repos],
        updated_at = [DateTime(r.updated_at[1:19]) for r in repos],
        language = [something(r.language, "Unknown") for r in repos],
        is_fork = [r.fork for r in repos],
    )
end

"""
    fetch_watched_repos()

Fetch repositories the user is watching.
"""
function fetch_watched_repos()
    username = CONFIG[][:username]
    repos = paginate_all("/users/$username/subscriptions")
    
    DataFrame(
        repo = [r.full_name for r in repos],
        description = [something(r.description, "") for r in repos],
        stars = [r.stargazers_count for r in repos],
        updated_at = [DateTime(r.updated_at[1:19]) for r in repos],
    )
end

"""
    fetch_all_activity()

Fetch all activity data for the configured user.
"""
function fetch_all_activity()
    @info "Fetching issues..."
    issues = fetch_my_issues()
    
    @info "Fetching PRs..."
    prs = fetch_my_prs()
    
    @info "Fetching comments..."
    comments = fetch_my_comments()
    
    @info "Fetching contributions..."
    contributions = fetch_contributions()
    
    @info "Fetching watched repos..."
    watched = fetch_watched_repos()
    
    Dict(
        :issues => issues,
        :prs => prs,
        :comments => comments,
        :contributions => contributions,
        :watched => watched,
        :fetched_at => now()
    )
end

# Statistics Computation

"""
    compute_stats(activity)

Compute statistics from fetched activity data.
"""
function compute_stats(activity::Dict)
    issues = activity[:issues]
    prs = activity[:prs]
    contributions = activity[:contributions]
    
    Dict(
        # Issue stats
        :total_issues => nrow(issues),
        :open_issues => count(==("open"), issues.state),
        :closed_issues => count(==("closed"), issues.state),
        :avg_issue_comments => mean(issues.comments),
        :issue_response_times => compute_response_times(issues),
        
        # PR stats
        :total_prs => nrow(prs),
        :open_prs => count(==("open"), prs.state),
        :merged_prs => count(!ismissing, prs.merged_at),
        :avg_pr_comments => mean(prs.comments),
        
        # Contribution stats
        :total_repos => nrow(contributions),
        :original_repos => count(!, contributions.is_fork),
        :total_stars => sum(contributions.stars),
        :languages => countmap(contributions.language),
        
        # Activity by time
        :issues_by_month => issues_by_month(issues),
        :prs_by_month => prs_by_month(prs),
        
        # Top repos
        :top_repos_by_issues => top_repos(issues, :repo, 10),
        :top_repos_by_prs => top_repos(prs, :repo, 10),
    )
end

function compute_response_times(issues::DataFrame)
    closed = filter(row -> !ismissing(row.closed_at), issues)
    if nrow(closed) == 0
        return missing
    end
    
    times = [Dates.value(row.closed_at - row.created_at) / (1000 * 60 * 60 * 24) 
             for row in eachrow(closed)]
    
    Dict(
        :mean_days => mean(times),
        :median_days => median(times),
        :min_days => minimum(times),
        :max_days => maximum(times),
    )
end

function issues_by_month(issues::DataFrame)
    issues.month = Dates.format.(issues.created_at, "yyyy-mm")
    countmap(issues.month)
end

function prs_by_month(prs::DataFrame)
    prs.month = Dates.format.(prs.created_at, "yyyy-mm")
    countmap(prs.month)
end

function top_repos(df::DataFrame, col::Symbol, n::Int)
    counts = countmap(df[!, col])
    sort(collect(counts), by=x->-x[2])[1:min(n, length(counts))]
end

# Output Functions

"""
    summary(stats)

Print a summary of the computed statistics.
"""
function summary(stats::Dict)
    println("=" ^ 60)
    println("GitHub Activity Summary")
    println("=" ^ 60)
    
    println("\n📝 Issues")
    println("  Total: $(stats[:total_issues])")
    println("  Open: $(stats[:open_issues])")
    println("  Closed: $(stats[:closed_issues])")
    println("  Avg comments: $(round(stats[:avg_issue_comments], digits=1))")
    
    if !ismissing(stats[:issue_response_times])
        rt = stats[:issue_response_times]
        println("  Avg close time: $(round(rt[:mean_days], digits=1)) days")
    end
    
    println("\n🔀 Pull Requests")
    println("  Total: $(stats[:total_prs])")
    println("  Open: $(stats[:open_prs])")
    println("  Merged: $(stats[:merged_prs])")
    
    println("\n📦 Repositories")
    println("  Total: $(stats[:total_repos])")
    println("  Original (non-fork): $(stats[:original_repos])")
    println("  Total stars: $(stats[:total_stars])")
    
    println("\n🔤 Top Languages")
    for (lang, count) in sort(collect(stats[:languages]), by=x->-x[2])[1:min(5, length(stats[:languages]))]
        println("  $lang: $count")
    end
    
    println("\n" * "=" ^ 60)
end

"""
    export_csv(stats, path)

Export statistics to CSV files.
"""
function export_csv(activity::Dict, dir::String)
    mkpath(dir)
    
    CSV.write(joinpath(dir, "issues.csv"), activity[:issues])
    CSV.write(joinpath(dir, "prs.csv"), activity[:prs])
    CSV.write(joinpath(dir, "contributions.csv"), activity[:contributions])
    CSV.write(joinpath(dir, "watched.csv"), activity[:watched])
    
    @info "Exported to $dir"
end

# Plotting

"""
    plot_contributions(stats)

Plot contribution timeline.
"""
function plot_contributions(stats::Dict)
    months = sort(collect(keys(stats[:issues_by_month])))
    counts = [stats[:issues_by_month][m] for m in months]
    
    plt = barplot(months[end-11:end], counts[end-11:end], 
                  title="Issues Created (Last 12 Months)",
                  xlabel="Month", ylabel="Count")
    display(plt)
end

"""
    plot_issue_timeline(activity)

Plot issue creation over time.
"""
function plot_issue_timeline(activity::Dict)
    issues = activity[:issues]
    dates = sort(issues.created_at)
    cumulative = 1:length(dates)
    
    plt = lineplot(dates, cumulative,
                   title="Cumulative Issues Created",
                   xlabel="Date", ylabel="Total Issues")
    display(plt)
end

end # module
