# Give content Markdown slashless URLs before Jekyll filters drafts.
Jekyll::Hooks.register :pages, :post_init do |page|
    next unless page.relative_path.start_with?("content/") &&
                page.site.find_converter_instance(Jekyll::Converters::Markdown).matches(page.ext)

    # Jekyll's publisher uses Hash#fetch, which bypasses lazy frontmatter defaults.
    page.data["published"] = page.data["published"]
    path = page.relative_path.delete_prefix("content/").delete_suffix(page.ext)
    path = path.sub(%r{[^/]+\z}) { |filename| filename.tr("_", "-") }
    permalink = (page.data["permalink"] || "/#{path}").sub(%r{/+\z}, "").delete_suffix(".html")
    # Jekyll appends .html to the destination, not the public URL.
    # Standalone routes resolve that backing file without a redirect.
    page.data["permalink"] = permalink.empty? ? "/" : permalink
end

# Parent routes also need an index when a host gives directories precedence.
# Keep the slashless page URL and HTML backing; both copies share its canonical.
Jekyll::Hooks.register :site, :post_write do |site|
    site.pages.each do |page|
        next unless page.output_ext == ".html" && !page.url.end_with?("/", ".html")

        backing = page.destination(site.dest)
        directory = backing.delete_suffix(".html")
        next unless File.directory?(directory)

        index = File.join(directory, "index.html")
        FileUtils.cp(backing, index) unless File.exist?(index)
    end
end

# Markdown without frontmatter would otherwise be copied publicly as a raw file.
Jekyll::Hooks.register :site, :post_read do |site|
    # Reserve the random page's public route and its native HTML backing file.
    random = site.pages.find { |page| page.relative_path == "content/haiku/_random.md" }
    if random
        backing = random.destination(site.dest)
        route = backing.delete_suffix(".html")
        collisions = [backing, route, File.join(route, "index.html")]
        (site.pages + site.static_files).each do |file|
            next if file.equal?(random) || !collisions.include?(file.destination(site.dest))

            raise Jekyll::Errors::FatalException,
                  "#{file.relative_path}: /haiku/random is reserved for content/haiku/_random.md."
        end
    end

    markdown = site.find_converter_instance(Jekyll::Converters::Markdown)
    site.static_files.each do |file|
        next unless file.relative_path.start_with?("/content/") && markdown.matches(file.extname)

        raise Jekyll::Errors::FatalException,
              "#{file.relative_path}: content Markdown requires YAML frontmatter (at least title:)."
    end
end
