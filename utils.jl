using Dates

function hfun_youtube(params)
    id = params[1]
    return """
        <div style=position:relative;padding-bottom:56.25%;height:0;overflow:hidden>
          <iframe
            src=https://www.youtube.com/embed/$id
            style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; border:0;"
            allowfullscreen
            title="YouTube Video">
          </iframe>
        </div>
        """
end

const MONTH = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
               "Aug", "Sep", "Oct", "Nov", "Dec"]

function blogpost_name(fp)
    lag = ifelse(endswith(fp, "index.md"), 1, 0)
    return splitpath(fp)[end-lag]
end

function getdate(fname)
    y, m, d, _ = split(fname, "-")
    return parse.(Int, (y, m, d))
end

function hfun_post_date()
    fname = blogpost_name(locvar(:fd_rpath)::String)
    y, m, d = getdate(fname)
    return """
           <i data-feather=calendar></i>
           <time datetime=$y-$m-$d>$(MONTH[m]) $d, $y</time>
           """
end

function blogpost_entry_html(link, title, y, m, d; ext=false)
    return """
        <p>
          <a class=font-125 href="$link">
            $title
          </a>$(ifelse(ext, "<span>&nbsp;&#8599;</span>", ""))
          <br>
          <i data-feather=calendar></i>
          <time datetime=$y-$m-$d>$(MONTH[m]) $d, $y</time>
        </p>
        """
end

function blogpost_entry(fpath)
    rpath = joinpath("post", fpath)
    if isdir(rpath)
        rpath = joinpath(rpath, "index.md")
    end
    hidden = pagevar(rpath, :hidden)
    !isnothing(hidden) && hidden && return nothing
    title = pagevar(rpath, :title)::String
    y, m, d = getdate(fpath)
    rpath = replace(fpath, r"\.md$" => "")
    date = Date(y, m, d)
    return (date, blogpost_entry_html("/post/$rpath/", title, y, m, d))
end

function blogpost_external_entries()
    return [(d, blogpost_entry_html(l, t, year(d), month(d), day(d); ext=true))
            for (d, t, l) in locvar(:external_entries)]
end

function hfun_blogposts()
    io = IOBuffer()
    elements = filter!(e -> e != "index.md", readdir("post"))
    entries = [blogpost_entry(fp) for fp in elements]
    entries = [e for e in entries if !isnothing(e)]
    append!(entries, blogpost_external_entries())
    sort!(entries, by=(e -> e[1]), rev=true)
    for entry in entries
        write(io, entry[2])
    end
    return String(take!(io))
end
