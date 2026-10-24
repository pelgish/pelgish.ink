# Build isolated fixture sites and verify the generated publishing contract.
require "jekyll"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "date"
require "time"
require "socket"
require "net/http"
require "cgi"

def check(condition, message)
    raise message unless condition
end

# Home retains its shell but never enumerates writing, including draft previews.
def check_home(html, years = Time.now.year == 2026 ? "2026" : "2026-#{Time.now.year}")
    main = html[/<main\b[^>]*>(.*?)<\/main>/m, 1]
    controls = main&.slice!(/<section class="home-controls" aria-label="Explore writing">.*?<\/section>/m)
    check(controls, "Home icon controls missing")
    prefix = html[/href="([^"]*)\/assets\/css\/style.css"/, 1]
    check(controls.include?("href=\"#{prefix}/haiku\"") &&
          controls.include?('aria-label="Haikus"'), "Haiku control must link to the haiku listing")
    check(controls.include?("<a class=\"icon-control\" href=\"#{prefix}/story\" aria-label=\"Short Stories\"") &&
          controls.scan(/\bhref=/).length == 2 && !controls.include?("disabled"),
          "Short Stories must be an accessible anchor to the slashless listing")
    check(controls.match?(/icon-haiku" aria-hidden="true"><\/span>\s*<span>Haikus<\/span>/) &&
          controls.match?(/icon-shortstory" aria-hidden="true"><\/span>\s*<span>Short Stories<\/span>/),
          "Home categories must show their visible labels after the icons")
    %w[haiku shortstory].each do |icon|
        check(controls.include?("<span class=\"control-icon icon-#{icon}\" aria-hidden=\"true\"></span>"),
              "Decorative home #{icon} icon missing")
    end
    check(main&.strip&.match?(/\A<section class="home-copyright" aria-label="Copyright">\s*<p>All content on this site is copyright\(c\) Connor Shugg #{Regexp.escape(years)}<\/p>\s*<p>Writing and images are of my own original creation\.<\/p>\s*<\/section>\z/),
          "Home must contain only its icon controls and unchanged copyright with years #{years}")
    check(html.index(controls) < html.index('class="home-copyright"'), "Controls must precede copyright")
    check(html.include?('<body class="home-page">'), "Home-only viewport layout hook missing")
    check(html.include?('rel="canonical"') && html.include?('class="site-header"'), "Home shell missing")
end

# The reader shares the site shell and exposes its host, status, and target list.
def random_targets(html)
    check(html.match?(/\A<!doctype html>(?:\s|<!--.*?-->)*<html\b/im) && html.rstrip.end_with?("</html>"),
          "Random page must be a complete HTML document")
    check(html.scan(/<header class="site-header">/).length == 1 &&
          html.scan(/<main id="main" tabindex="-1">/).length == 1 &&
          html.include?('id="appearance-toggle" class="icon-control" type="button" hidden'),
          "Random reader must use one shared shell with the appearance control")
    main = html[/<main\b[^>]*>(.*?)<\/main>/m, 1]
    check(main&.match?(/<div id="haiku-content">\s*<\/div>/) &&
          main.match?(/<p id="haiku-status" role="status" hidden(?:="")?>\s*<\/p>/),
          "Random reader must start with an empty content host and hidden accessible status")
    check(main.match?(/<noscript>\s*<p>Enable JavaScript to read a random haiku on this page\.<\/p>\s*<\/noscript>/),
          "Random reader must explain the JavaScript requirement without JS")
    check(main.match?(/<div id="haiku-content">\s*<\/div>\s*<button id="haiku-another" class="icon-control hero-control" type="button" aria-label="Get a new haiku" title="Get a new haiku" hidden(?:="")?>\s*<span class="control-icon icon-arrowcircle icon-spin" aria-hidden="true"><\/span>\s*<span>Get a new haiku<\/span>\s*<\/button>/) &&
          main.scan(/id="haiku-another"/).length == 1,
          "Accessible arrow-circle button must start hidden and follow the haiku host")
    check(!html.include?('class="home-page"') && !html.include?('class="home-copyright"') &&
          !html.include?("All content on this site is copyright(c)"),
          "Home layout or copyright leaked into the random reader")
    canonical = html[/rel="canonical" href="([^"]+)"/, 1]
    check(canonical && URI(canonical).path.delete_prefix("/preview") == "/haiku/random",
          "Random canonical must be slashless")
    prefix = URI(canonical).path.delete_suffix("/haiku/random")
    check(html.include?('<meta charset="utf-8">') &&
          html.scan(/<script\b[^>]*src="([^"]+)"/).flatten ==
              ["#{prefix}/assets/js/appearance.js", "#{prefix}/assets/js/random-haiku.js"] &&
          html.include?("src=\"#{prefix}/assets/js/random-haiku.js\" defer>") &&
          html.include?("href=\"#{prefix}/assets/css/style.css\""),
          "Random reader must load the shared appearance/styles and deferred reader with the URL prefix")
    check(main.scan(/<script id="haiku-targets" type="application\/json">/).length == 1,
          "Random reader must have exactly one generated target list")
    JSON.parse(main[/<script id="haiku-targets" type="application\/json">(.*?)<\/script>/m, 1])
end

# Use the same configuration as the real site, with temporary source/output paths.
def build(source, options = {})
    destination = File.join(source, "_site")
    config = Jekyll.configuration(
        "source" => source,
        "destination" => destination,
        "quiet" => true,
        **options
    )
    Jekyll::Site.new(config).process
    destination
end

root = File.expand_path("..", __dir__)

# Invoke the actual executable, preserving the supplied working directory.
def publication(script, arguments, directory)
    stdout, stderr, status = Open3.capture3(script, *arguments, chdir: directory)
    check(status.success?, "publish.sh #{arguments.inspect} failed: #{stderr}")
    stdout
end

# Read test metadata safely while keeping body preservation assertions byte-based.
def frontmatter(path)
    YAML.safe_load(File.read(path).split(/^---[ \t]*\r?$/, 3)[1],
                   permitted_classes: [Date, Time], aliases: true)
end

publisher = File.join(root, "scripts/publish.sh")
check(File.executable?(publisher), "publish.sh must be executable")
Dir.mktmpdir("pelgish-publish-check-") do |directory|
    path = File.join(directory, "a poem.md")
    body = "  A line with spaces  \r\nNext line\\\r\n\r\nFinal stanza without newline"
    header = "---\r\n# Keep this comment\r\ntitle: 'A: poem' # title comment\r\ndate: 2020-01-02\r\nother: {enabled: true, count: 3}\r\ndescription: |\r\n  Two lines\r\n  remain here.\r\n---\r\n"
    original = header + body
    File.binwrite(path, original)
    File.chmod(0o640, path)
    before = Time.now.utc
    publication(publisher, ["a poem.md"], directory)
    after = Time.now.utc
    data = frontmatter(path)
    check(data["published"] == true, "Publication must persist a boolean true")
    timestamp = data["published_timestamp"]
    check(timestamp.is_a?(String) && timestamp.match?(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/), "Timestamp must be ISO8601 UTC")
    check(Time.iso8601(timestamp).to_i.between?(before.to_i, after.to_i), "Timestamp must be current UTC")
    check(File.binread(path).end_with?(body), "Poetry body bytes changed")
    check(File.stat(path).mode & 0o777 == 0o640, "Permission bits changed")
    check(data.reject { |key, _| %w[published published_timestamp].include?(key) } ==
          YAML.safe_load(header.split("---")[1], permitted_classes: [Date]), "Other metadata changed")

    # An old persistent timestamp makes refresh testing deterministic without sleeping.
    File.binwrite(path, File.binread(path).sub(timestamp, "2000-01-01T00:00:00Z"))
    publication(publisher, [path], root)
    check(frontmatter(path)["published_timestamp"] != "2000-01-01T00:00:00Z", "Republish preserved an old timestamp")
    publication(publisher, [path, "--unpublish"], root)
    check(File.binread(path) == original, "Unpublish must restore unrelated formatting/comments/body")
    publication(publisher, ["--unpublish", path], directory)
    check(File.binread(path) == original, "Repeated unpublish changed the file")

    # Flow-style mappings, quoted publication keys, and multiline values use real YAML parsing.
    ["{title: Flow, date: 2020-01-02, other: [1, true]}\n",
     "  title: Indented\n  other: true\n",
     "title: Aliases\nbase: &base {count: 3}\ncopy: *base\n",
     "title: Unicode café\nother: naïve\n",
     "title: Block\n\"published\": false # old flag\npublished_timestamp: |\n  old timestamp\n"].each do |yaml|
        File.write(path, "---\n#{yaml}---\n#{body}")
        expected = frontmatter(path).reject { |key, _| %w[published published_timestamp].include?(key) }
        publication(publisher, [path], directory)
        check(frontmatter(path).reject { |key, _| %w[published published_timestamp].include?(key) } == expected,
              "Flow/multiline metadata changed")
        check(File.binread(path).end_with?(body), "Flow/multiline body changed")
        publication(publisher, ["--unpublish", path], directory)
        check(frontmatter(path) == expected, "Flow/multiline unpublish failed")
    end

    # Every invalid invocation must leave every input unchanged, without temporary artifacts.
    invalid = [
        "No frontmatter\n", "---\ntitle: [broken\n---\nbody\n",
        "---\n- list\n---\nbody\n", "---\nscalar\n---\nbody\n",
        "---\n---\nbody\n", "---\ntitle: Missing close\n",
        "---\npublished: false\n'published': true\n---\nbody\n",
        "---\npublished_timestamp: old\npublished_timestamp: new\n---\nbody\n",
        "---\nvalue: !ruby/object:Object {}\n---\nbody\n",
        "---\nbase: &base {published: true}\n<<: *base\n---\nbody\n"
    ]
    invalid.each do |text|
        File.write(path, text)
        [[path], ["--unpublish", path]].each do |arguments|
            _, stderr, status = Open3.capture3(publisher, *arguments, chdir: directory)
            check(!status.success? && stderr.include?("publish.sh:"), "Invalid frontmatter accepted")
            check(File.binread(path) == text.b, "Invalid frontmatter was rewritten")
        end
    end
    File.binwrite(path, original)
    non_markdown = File.join(directory, "data.txt")
    File.binwrite(non_markdown, original)
    link = File.join(directory, "link.md")
    File.symlink(path, link)
    [[], [""], ["--unpublish"], ["--unknown", path], [path, path],
     ["--unpublish", path, "--unpublish"], ["missing.md"], [directory], [non_markdown], [link]].each do |arguments|
        _, stderr, status = Open3.capture3(publisher, *arguments, chdir: directory)
        check(!status.success? && stderr.include?("publish.sh:"), "Invalid arguments accepted: #{arguments.inspect}")
        check(File.binread(path) == original && File.binread(non_markdown) == original, "Invalid arguments edited input")
    end
    check(Dir.children(directory).sort == ["a poem.md", "data.txt", "link.md"], "Publish left helper artifacts")
end
puts "PASS: publication CLI persistence, fresh UTC timestamps, safe errors, bytes, modes, spaces, cwd, and idempotence"

# Stub Bundler to check wrapper arguments without starting a preview server.
Dir.mktmpdir("pelgish-serve-check-") do |directory|
    scripts = File.join(directory, "scripts")
    FileUtils.mkdir_p(scripts)
    FileUtils.cp(File.join(root, "scripts/serve.sh"), scripts)
    bundle = File.join(scripts, "bundle.sh")
    File.write(bundle, <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        if ARGV[0, 3] == %w[exec jekyll serve]
            puts JSON.generate("args" => ARGV, "cwd" => Dir.pwd)
        end
    RUBY
    FileUtils.chmod(0o755, bundle)
    environment = { "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLER_SETUP" => nil }
    script = File.join(scripts, "serve.sh")
    cases = [
        [[], [], "14000"],
        [["4001"], ["--port", "4001"], "14001"],
        [["4001", "--show-unpublished", "--host", "127.0.0.1"], ["--port", "4001", "--unpublished", "--host", "127.0.0.1"], "14001"],
        [["1"], ["--port", "1"], "10001"],
        [["65535"], ["--port", "65535"], "55535"],
        [["55535"], ["--port", "55535"], "65535"],
        [["55536"], ["--port", "55536"], "45536"],
        [["0004001"], ["--port", "4001"], "14001"],
        [["--show-unpublished"], ["--unpublished"], "14000"],
        [["--port", "4001"], ["--port", "4001"], "14001"],
        [["--port=4001"], ["--port=4001"], "14001"],
        [["-P", "4001"], ["-P", "4001"], "14001"],
        [["-P3999", "--show-unpublished"], ["-P3999", "--unpublished"], "13999"],
        [["--port", "3999", "--show-unpublished"], ["--port", "3999", "--unpublished"], "13999"],
        [["--baseurl", "/a path", "--show-unpublished"], ["--baseurl", "/a path", "--unpublished"], "14000"],
        [["--show-unpublished", "--port", "4001", "--quiet"], ["--unpublished", "--port", "4001", "--quiet"], "14001"],
        [["--host=127.0.0.1", "--show-unpublished", "--future"], ["--host=127.0.0.1", "--unpublished", "--future"], "14000"],
        [["4001", "--show-unpublished", "--livereload-port", "14002"], ["--port", "4001", "--unpublished", "--livereload-port", "14002"], nil],
        [["--livereload-port=14002", "--port=3999", "--show-unpublished"], ["--livereload-port=14002", "--port=3999", "--unpublished"], nil]
    ]
    cases.each do |arguments, forwarded, livereload_port|
        stdout, stderr, status = Open3.capture3(environment, script, *arguments, chdir: root)
        check(status.success?, "serve.sh #{arguments.inspect} failed: #{stderr}")
        result = JSON.parse(stdout)
        defaults = livereload_port ? ["--livereload-port", livereload_port] : []
        check(result["args"] == %w[exec jekyll serve --livereload] + forwarded + defaults, "Incorrect forwarding for #{arguments.inspect}")
        check(result["cwd"] == directory, "Incorrect repository resolution")
    end

    # Invalid positional ports and competing selectors must fail before Bundler runs.
    ["", "0", "-1", "65536", "999999999999999999999", "abc", "4.5", "4001x"].each do |port|
        stdout, stderr, status = Open3.capture3(environment, script, port)
        check(!status.success? && stdout.empty? && stderr.include?("serve.sh: invalid port") && stderr.include?("1 to 65535"),
              "Missing invalid-port error for #{port.inspect}")
    end
    [["--port", "4002"], ["--port=4002"], ["-P", "4002"], ["-P4002"]].each do |options|
        stdout, stderr, status = Open3.capture3(environment, script, "4001", *options)
        check(!status.success? && stdout.empty? && stderr.include?("serve.sh: choose either"),
              "Missing duplicate-port error for #{options.inspect}")
    end
    [["--port"], ["-P"], ["--port", "0"], ["--port=65536"], ["-Pabc"]].each do |options|
        stdout, stderr, status = Open3.capture3(environment, script, *options)
        check(!status.success? && stdout.empty? && stderr.include?("HTTP port must be an integer"),
              "Invalid HTTP selector reached LiveReload arithmetic: #{options.inspect}")
    end
    ["--unpublished", "--unpublished=true"].each do |option|
        stdout, stderr, status = Open3.capture3(environment, script, "4001", "--quiet", option)
        check(!status.success? && stdout.empty? && stderr.include?("use --show-unpublished instead"),
              "Legacy preview option must fail with migration guidance")
    end
    stdout, stderr, status = Open3.capture3(environment, script, "--help")
    check(status.success? && stderr.empty? && stdout.include?("--show-unpublished"), "Preview help is missing")
end
puts "PASS: preview wrapper default, positional ports, forwarding, repository resolution, and errors"

# Prove that the launcher can use a local Bundler when none is globally visible.
Dir.mktmpdir("pelgish-bundler-check-") do |directory|
    scripts = File.join(directory, "scripts")
    FileUtils.mkdir_p(scripts)
    FileUtils.cp(File.join(root, "scripts/bundle.sh"), scripts)
    specification = Gem.loaded_specs.fetch("bundler")
    File.write(File.join(directory, "Gemfile.lock"), "BUNDLED WITH\n  #{specification.version}\n")
    environment = {
        "GEM_HOME" => File.join(directory, "empty"), "GEM_PATH" => File.join(directory, "empty"),
        "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLER_SETUP" => nil
    }
    script = File.join(scripts, "bundle.sh")
    _, stderr, status = Open3.capture3(environment, script, "--version")
    check(!status.success? && stderr.include?("run scripts/setup-dependencies.sh"), "Missing locked Bundler was not reported")
    tools = File.join(directory, ".bundle/tools")
    FileUtils.mkdir_p([File.join(tools, "gems"), File.join(tools, "specifications")])
    FileUtils.cp_r(specification.full_gem_path, File.join(tools, "gems"))
    File.write(File.join(tools, "specifications", "bundler-#{specification.version}.gemspec"), specification.to_ruby)
    stdout, stderr, status = Open3.capture3(environment, script, "--version", chdir: "/")
    check(status.success? && stdout.include?(specification.version.to_s), "Local locked Bundler failed: #{stderr}")
end
puts "PASS: locked Bundler launcher uses project-local gems without global Bundler or PATH changes"

# Isolate setup from real package managers and gem installs. Stubs log every action.
Dir.mktmpdir("pelgish-setup-check-") do |directory|
    scripts = File.join(directory, "scripts")
    bin = File.join(directory, "bin")
    FileUtils.mkdir_p([scripts, bin])
    FileUtils.cp(File.join(root, "scripts/setup-dependencies.sh"), scripts)
    File.write(File.join(directory, "Gemfile.lock"), "BUNDLED WITH\n  4.0.9\n")
    log = File.join(directory, "commands.jsonl")
    marker = File.join(directory, "missing-bundler")
    # Use an absolute interpreter: the stub's own dependencies cannot escape PATH isolation.
    stub = <<~RUBY
        #!#{RbConfig.ruby}
        require "json"
        name = File.basename($0)
        File.open(ENV.fetch("SETUP_LOG"), "a") { |file| file.puts JSON.generate([name, *ARGV]) }
        case name
        when "uname"
            puts ENV.fetch("SETUP_OS", "Linux")
        when "ruby"
            exit 1 if ENV["SETUP_BAD_RUBY"] && ARGV.include?('-e') && ARGV.last.include?('Gem::Requirement')
            exec #{RbConfig.ruby.inspect}, *ARGV
        when "bundle.sh"
            abort "Bundle must run frozen" unless ENV["BUNDLE_FROZEN"] == "true" || ARGV == ["--version"]
            exit 1 if ARGV == ["--version"] && File.exist?(ENV.fetch("SETUP_MARKER"))
            exit 1 if ARGV == ["check"] && ENV["SETUP_NEEDS_INSTALL"]
            exit 23 if ARGV == ["install"] && ENV["SETUP_FAIL_INSTALL"]
        when "gem"
            File.unlink(ENV.fetch("SETUP_MARKER")) if File.exist?(ENV.fetch("SETUP_MARKER"))
        when "sudo"
            exec(*ARGV)
        when "apt-get"
            exit 29 if ENV["SETUP_FAIL_APT"]
            if ARGV.first == "install"
                File.symlink(File.join(File.dirname($0), "stub"), File.join(File.dirname($0), "pkg-config"))
            end
        end
    RUBY
    File.write(File.join(bin, "stub"), stub)
    FileUtils.chmod(0o755, File.join(bin, "stub"))
    %w[ruby gem make gcc g++ pkg-config uname sudo apt-get].each do |name|
        File.symlink(File.join(bin, "stub"), File.join(bin, name))
    end
    %w[bash dirname].each do |name|
        tool, status = Open3.capture2("which", name)
        check(status.success?, "Cannot locate #{name} for setup checks")
        File.symlink(tool.strip, File.join(bin, name))
    end
    File.write(File.join(scripts, "bundle.sh"), stub)
    FileUtils.chmod(0o755, File.join(scripts, "bundle.sh"))
    environment = {
        "PATH" => bin, "SETUP_LOG" => log, "SETUP_MARKER" => marker,
        "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLER_SETUP" => nil
    }
    script = File.join(scripts, "setup-dependencies.sh")
    run = lambda do |arguments = [], extra = {}|
        File.write(log, "")
        stdout, stderr, status = Open3.capture3(environment.merge(extra), script, *arguments, chdir: "/")
        commands = File.readlines(log).map { |line| JSON.parse(line) }
        [stdout, stderr, status, commands]
    end

    stdout, _, status, commands = run.call(["--help"])
    check(status.success? && stdout.include?("--install-system-dependencies") && commands.empty?, "Setup help requires tools")
    _, stderr, status, commands = run.call(["--unknown"])
    check(!status.success? && stderr.include?("unknown argument") && commands.empty?, "Setup accepted unknown arguments")
    File.unlink(File.join(bin, "ruby"))
    _, stderr, status, commands = run.call
    check(!status.success? && stderr.include?("missing prerequisite: ruby") &&
          commands.none? { |command| %w[apt-get sudo gem bundle.sh].include?(command.first) }, "Missing Ruby was not handled safely")
    File.symlink(File.join(bin, "stub"), File.join(bin, "ruby"))
    File.unlink(File.join(bin, "pkg-config"))
    _, stderr, status, commands = run.call
    check(!status.success? && stderr.include?("pkg-config") &&
          (stderr.include?("--install-system-dependencies") || stderr.include?("manually")), "Missing prerequisite guidance failed")
    check(commands.none? { |command| %w[apt-get sudo gem bundle.sh].include?(command.first) }, "Setup mutated without opt-in")
    _, stderr, status, commands = run.call(["--install-system-dependencies"], { "SETUP_OS" => "Darwin" })
    check(!status.success? && stderr.include?("only Debian/Ubuntu"), "Unsupported system install was accepted")
    check(commands.none? { |command| %w[apt-get sudo].include?(command.first) }, "Unsupported platform invoked apt")
    # Apt paths are valid only on the supported host family; never invoke real apt/sudo.
    if File.file?("/etc/os-release") && File.read("/etc/os-release").match?(/^ID=(?:ubuntu|debian)$/)
        _, stderr, status, commands = run.call(["--install-system-dependencies"], { "SETUP_FAIL_APT" => "1" })
        check(!status.success? && commands.include?(["apt-get", "update"]) &&
              commands.none? { |command| command == ["bundle.sh", "check"] }, "Apt failure was masked")
        stdout, stderr, status, commands = run.call(["--install-system-dependencies"])
        check(status.success?, "Stub system setup failed: #{stderr}")
        check(commands.include?(["apt-get", "update"]) &&
              commands.any? { |command| command[0, 3] == ["apt-get", "install", "-y"] }, "Opt-in did not install prerequisites")
    else
        File.symlink(File.join(bin, "stub"), File.join(bin, "pkg-config"))
    end
    _, stderr, status, commands = run.call([], { "SETUP_BAD_RUBY" => "1" })
    check(!status.success? && stderr.include?("Ruby >=3.2 and <4") &&
          commands.none? { |command| command.first == "gem" }, "Unsupported Ruby was accepted")
    File.write(marker, "")
    stdout, stderr, status, commands = run.call
    check(status.success? && stdout.include?("./scripts/bundle.sh exec ruby scripts/check.rb"), "Setup failed: #{stderr}")
    install = commands.find { |command| command[0, 3] == ["gem", "install", "bundler"] }
    check(install && install.include?("4.0.9") && install.last == File.join(directory, ".bundle/tools"), "Bundler installation is not locked/local")
    _, stderr, status, commands = run.call
    check(status.success? && commands.none? { |command| %w[gem apt-get sudo].include?(command.first) }, "Second setup was not idempotent: #{stderr}")
    _, _, status, commands = run.call([], { "SETUP_NEEDS_INSTALL" => "1", "SETUP_FAIL_INSTALL" => "1" })
    check(!status.success? && commands.include?(["bundle.sh", "install"]), "Bundle install failure was masked")
    check(File.read(File.join(directory, "Gemfile.lock")) == "BUNDLED WITH\n  4.0.9\n", "Setup changed the lockfile")
end
puts "PASS: setup help/errors, missing prerequisites, opt-in/unsupported systems, local locked Bundler, idempotence, and failure propagation"

Dir.mktmpdir("pelgish-check-") do |source|
    %w[_config.yml _plugins _layouts assets index.md story.md haiku.md CNAME].each do |path|
        FileUtils.cp_r(File.join(root, path), source)
    end
    FileUtils.mkdir_p(File.join(source, "content/haiku"))
    structural_source = File.join(source, "content/haiku/_random.md")
    FileUtils.cp(File.join(root, "content/haiku/_random.md"), structural_source)
    structural_bytes = File.binread(structural_source)

    # Control build time and YAML types to verify single years, ranges, and fallback.
    config_path = File.join(source, "_config.yml")
    original_config = File.read(config_path)
    [
        [2026, 2026, "2026"],
        ["2026", 2026, "2026"],
        [2026, 2027, "2026-2027"],
        ["2026", 2027, "2026-2027"],
        [nil, 2026, "2026"],
        [nil, 2027, "2026-2027"],
        [2025, 2027, "2025-2027"]
    ].each do |start_year, end_year, expected|
        config = YAML.safe_load(original_config)
        if start_year.nil?
            config.delete("copyright_start_year")
        else
            config["copyright_start_year"] = start_year
        end
        File.write(config_path, YAML.dump(config))
        output = build(source, "time" => Time.utc(end_year, 6, 15))
        check_home(File.read(File.join(output, "index.html")), expected)
        check(random_targets(File.read(File.join(output, "haiku/random.html"))) == [],
              "Random reader must exclude itself when no haiku are published")
    end
    File.write(config_path, original_config)
    puts "PASS: home controls/copyright, numeric/string start years, missing-setting fallback, and controlled build-year ranges"

    output = build(source)
    check_home(File.read(File.join(output, "index.html")))
    check(!File.exist?(File.join(root, "index.html")), "Duplicate root source")
    check(!File.exist?(File.join(root, "story.html")), "Story listing source must be Markdown only")
    check(!File.exist?(File.join(output, "story.md")), "Raw story listing Markdown leaked")
    check(!File.exist?(File.join(output, "index.md")), "Raw home Markdown leaked")
    random_path = File.join(output, "haiku/random.html")
    empty_random = File.read(random_path)
    check(random_targets(empty_random) == [], "Empty random reader must exclude itself")
    check(!File.exist?(File.join(output, "haiku/_random.html")) &&
          !File.exist?(File.join(output, "content")), "Underscore source leaked or ignored its permalink")
    check(!frontmatter(structural_source).key?("published_timestamp"), "Structural page needs no publication timestamp")

    # The static story listing is empty until actual story sources opt in.
    story_path = File.join(output, "story.html")
    empty_story = File.read(story_path)
    check(empty_story.match?(/<h1\b[^>]*>Short Stories<\/h1>/) &&
          empty_story.include?("No short stories have been published yet.") &&
          empty_story.include?('rel="canonical" href="https://pelgish.ink/story"') &&
          !File.exist?(File.join(output, "story")),
          "Empty story listing must use a slashless canonical with HTML backing")
    story_fixtures = {
        "story/alpha.md" => "title: 'A <script> & \"story\"'\npublished: true\n",
        "story/nested/untitled.md" => "published: true\n",
        "story/blank.md" => "title: '  '\npublished: true\n",
        "story/override.md" => "title: Override\npublished: true\npermalink: /elsewhere/story.html\n",
        "story/draft.md" => "title: Explicit draft\npublished: false\n",
        "story/implicit.md" => "title: Implicit draft\n",
        "story/index.md" => "title: Structural index\npublished: true\n",
        "story/nested/random.md" => "title: Structural random\npublished: true\n",
        "story/structure.md" => "title: Structural page\npublished: true\nliterary_content: false\n",
        "story/not-markdown.html" => "title: HTML page\npublished: true\n",
        "storyish/other.md" => "title: Other folder\npublished: true\npermalink: /story/other\n"
    }
    story_fixtures.each do |name, metadata|
        path = File.join(source, "content", name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "---\n#{metadata}---\nFixture body.\n")
    end
    [false, true].product(["", "/preview"]).each do |unpublished, baseurl|
        build(source, "unpublished" => unpublished, "baseurl" => baseurl)
        html = File.read(story_path)
        main = html[/<main\b[^>]*>(.*?)<\/main>/m, 1]
        expected = [
            ["/story/alpha", "A &lt;script&gt; &amp; &quot;story&quot;"],
            ["/story/blank", "blank"],
            ["/elsewhere/story", "Override"],
            ["/story/nested/untitled", "untitled"]
        ].map { |url, title| [baseurl + url, title] }
        links = main.scan(/<li><a href="([^"]+)">([^<]*)<\/a><\/li>/)
        check(links == expected,
              "Story list must include only published Markdown stories, safely titled and deterministically ordered: #{links.inspect}")
        check(!main.include?("No short stories") && !main.include?("<script") &&
              !main.include?("<time") && !main.include?("Fixture body."),
              "Story listing must be static links without bodies, dates, or client fetching")
        check(html.include?("rel=\"canonical\" href=\"https://pelgish.ink#{baseurl}/story\"") &&
              html.include?("href=\"#{baseurl}/assets/css/style.css\"") &&
              html.include?('id="appearance-toggle"') &&
              html.include?('data-color-scheme="grapevine"') &&
              html.include?('family=Cantarell:') &&
              html.scan(/<header class="site-header">/).length == 1,
              "Story listing must retain the shared shell, theme, fonts, and baseurl")
        check_home(File.read(File.join(output, "index.html")))
    end
    story_fixtures.each_key { |name| File.unlink(File.join(source, "content", name)) }
    build(source)
    puts "PASS: static story listing empty/multiple, drafts in previews, nested sources, overrides, escaped/fallback titles, structural exclusions, baseurl, and home link"

    # Haiku listing uses source membership, safe labels and actual generated routes.
    haiku_path = File.join(output, "haiku.html")
    check(File.read(haiku_path).include?("No haikus have been published yet."),
          "Empty haiku listing must have a meaningful message")
    check(File.read(File.join(output, "haiku/index.html")) == File.read(haiku_path),
          "Directory-backed haiku index must match its slashless HTML backing")
    haiku_fixtures = {
        "haiku/alpha_verse.md" => "title: 'A <verse> & \"haiku\"'\npublished: true\n",
        "haiku/nested_folder/blank_title.md" => "title: '  '\npublished: true\n",
        "haiku/override.md" => "published: true\npermalink: /elsewhere/kept_underscore\n",
        "haiku/untitled.markdown" => "published: true\n",
        "haiku/draft.md" => "title: Draft\npublished: false\n",
        "haiku/implicit.md" => "title: Implicit draft\n",
        "haiku/structure.md" => "published: true\nliterary_content: false\n",
        "haikuish/other.md" => "published: true\n",
        "story/gatekeeper_of_bree.md" => "published: true\n"
    }
    haiku_fixtures.each do |name, metadata|
        path = File.join(source, "content", name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "---\n#{metadata}---\nFixture body.\n")
    end
    [false, true].product(["", "/preview"]).each do |unpublished, baseurl|
        build(source, "unpublished" => unpublished, "baseurl" => baseurl)
        html = File.read(haiku_path)
        main = html[/<main\b[^>]*>(.*?)<\/main>/m, 1]
        check(main.match?(/\A\s*(?:<!--.*?-->\s*)?<div class="haiku-heading">\s*<h1\b[^>]*>Haikus<\/h1>\s*<a class="icon-control" href="#{Regexp.escape(baseurl)}\/haiku\/random" aria-label="Read a random haiku" title="Read a random haiku">\s*<span class="control-icon icon-arrowcircle icon-spin" aria-hidden="true"><\/span>\s*<\/a>\s*<\/div>\s*<ul>/m) &&
              main.scan(/aria-label="Read a random haiku"/).length == 1 &&
              !main.include?("hero-control"),
              "Haiku listing must share one row between its heading and compact accessible arrow-circle control")
        expected = [
            ["/haiku/alpha-verse", "A &lt;verse&gt; &amp; &quot;haiku&quot;"],
            ["/haiku/nested_folder/blank-title", "blank_title"],
            ["/elsewhere/kept_underscore", "override"],
            ["/haiku/untitled", "untitled"]
        ].map { |url, title| [baseurl + url, title] }
        links = main.scan(/<li><a href="([^"]+)">([^<]*)<\/a><\/li>/)
        check(links == expected,
              "Haiku listing must exclude drafts/self and preserve escaped/fallback labels, nested routes and overrides: #{links.inspect}")
        check(html.include?("rel=\"canonical\" href=\"https://pelgish.ink#{baseurl}/haiku\"") &&
              main.include?("href=\"#{baseurl}/haiku/random\"") &&
              !main.include?("No haikus") && !main.include?("Fixture body."),
              "Haiku index must use the shared canonical, link to random, and list links not bodies")
        (expected.map(&:first) + ["#{baseurl}/story/gatekeeper-of-bree"]).each do |url|
            route = url.delete_prefix(baseurl)
            backing = File.join(output, "#{route.delete_prefix("/")}.html")
            check(File.read(backing).include?("rel=\"canonical\" href=\"https://pelgish.ink#{url}\""),
                  "Generated canonical/backing must use the public slug: #{url}")
        end
        check(File.read(story_path).include?("href=\"#{baseurl}/story/gatekeeper-of-bree\""),
              "Story links must use dashed filename URLs")
        %w[haiku story].each do |route|
            check(File.read(File.join(output, route, "index.html")) == File.read(File.join(output, "#{route}.html")),
                  "Parent route index must match slashless backing: #{route}")
        end
        check(!File.exist?(File.join(output, "content")) &&
              !File.exist?(File.join(output, "story/gatekeeper_of_bree.html")) &&
              !File.exist?(File.join(output, "haiku/alpha_verse.html")),
              "Source prefixes and default underscore filenames must not leak into output")
        check_home(File.read(File.join(output, "index.html")))
    end
    haiku_fixtures.each_key { |name| File.unlink(File.join(source, "content", name)) }
    build(source)
    puts "PASS: haiku index, publication filtering, filename slugs, unchanged folders/overrides, links, canonicals and HTML backing"

    # Native underscore discovery and URL serialization also work with exactly one target.
    single = File.join(source, "content/haiku/only.md")
    File.write(single, "---\npublished: true\npermalink: '/elsewhere/one two&\"three\"<end'\n---\nOnly body.\n")
    build(source)
    check(random_targets(File.read(random_path)) == ["/elsewhere/one%20two&%22three%22%3Cend"],
          "Single overridden target was not safely encoded/serialized")
    File.unlink(single)

    # Markdown hard breaks must become actual br elements, with separate stanzas.
    fixtures = {
        "prose" => "---\ntitle: 'A & B'\nlayout: prose\n---\n# Authored heading\n\nParagraph one.\n\nParagraph two.\n",
        "poem" => "---\ntitle: 'Verse fixture'\nlayout: poetry\nreading_theme: ink\n---\nLine one\\\nLine two\n\nStanza two.\n",
        "draft" => "---\ntitle: 'Unpublished fixture'\nlayout: prose\n---\nDraft body.\n",
        "explicit-draft" => "---\ntitle: 'Explicit draft'\npublished: false\n---\nDraft body.\n",
        "stable" => "---\ntitle: 'Stable URL'\npermalink: /custom/path\ncolor_scheme: grapevine\nreading_theme: paper\n---\nStable body.\n",
        "haiku/haiku1" => "---\ntitle: 'Haiku <script> & fixture'\nlayout: poetry\n---\nFixture body.\n",
        "haiku/20260620-001" => "---\nlayout: poetry\n---\nUntitled fixture body.\n",
        "haiku/nested/haiku1" => "---\ntitle: 'Nested fixture'\nlayout: poetry\n---\nNested body.\n",
        "haiku/override" => "---\ntitle: 'Overridden haiku'\npermalink: /elsewhere/verse.html\n---\nOverride body.\n",
        "haiku/draft" => "---\ntitle: 'Haiku draft'\npublished: false\n---\nDraft haiku body.\n",
        "not-haiku" => "---\ntitle: 'Not a haiku'\npermalink: /haiku/not-a-haiku\n---\nOther body.\n",
        "html-override" => "---\ntitle: 'HTML override'\npermalink: /custom/page.html\n---\nHTML body.\n",
        "slash-override" => "---\ntitle: 'Slash override'\npermalink: /custom/slash/\n---\nSlash body.\n"
    }
    urls = fixtures.keys.to_h { |name| [name, "/#{name}"] }.merge(
        "stable" => "/custom/path", "html-override" => "/custom/page",
        "slash-override" => "/custom/slash", "haiku/override" => "/elsewhere/verse",
        "not-haiku" => "/haiku/not-a-haiku"
    )
    # Native Jekyll pages write HTML backing files for extensionless permalinks.
    output_path = lambda do |destination, name|
        url = urls.fetch(name).delete_prefix("/")
        File.join(destination, "#{url}.html")
    end
    fixtures.each do |name, text|
        path = File.join(source, "content", "#{name}.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
    end
    output = build(source)
    index = File.read(File.join(output, "index.html"))
    fixtures.each_key do |name|
        check(!File.exist?(output_path.call(output, name)), "Default-unpublished URL leaked: #{name}")
    end
    check_home(index)
    # A published child forces real parent-directory precedence during HTTP checks.
    served_story = File.join(source, "content/story/served.md")
    File.write(served_story, "---\ntitle: Served story\npublished: true\n---\nServed story body.\n")
    FileUtils.rm_r(output)
    # Use a fixed second loopback address so the user's localhost previews stay untouched.
    # CI and automatic local setup target Linux, where 127.0.0.2 is also loopback.
    fixture_host = "127.0.0.2"
    collision_listener = TCPServer.new(fixture_host, 45729)
    pids = []
    logs = []
    destinations = []
    script = File.join(root, "scripts/serve.sh")
    spawn_preview = lambda do |name, options|
        log = File.join(source, "_#{name}.log")
        destination = File.join(source, "_#{name}")
        logs << log
        destinations << destination
        pid = Process.spawn(script, *options, "--host", fixture_host,
                            "--source", source, "--destination", destination,
                            "--no-watch", "--disable-disk-cache", out: log, err: [:child, :out])
        pids << pid
        [pid, log]
    end
    request = lambda do |port, path|
        http = Net::HTTP.new(fixture_host, port, nil)
        http.open_timeout = 1
        http.read_timeout = 1
        http.get(path)
    end
    begin
        # An explicitly occupied LiveReload port must still fail, never switch ports.
        pid, log = spawn_preview.call("collision", ["--port", "3999", "--show-unpublished",
                                                   "--livereload-port", "45729"])
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
        loop do
            result = Process.waitpid2(pid, Process::WNOHANG)
            if result
                pids.delete(pid)
                check(!result.last.success? && File.read(log).include?("no acceptor"),
                      "Occupied LiveReload port did not fail as expected:\n#{File.read(log)}")
                break
            end
            check(Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline,
                  "Occupied LiveReload port unexpectedly kept running:\n#{File.read(log)}")
            sleep 0.1
        end

        # Start parallel default pairings and an explicit override while the listener stays bound.
        previews = [
            [3999, 13999, "http_a", ["--port", "3999", "--show-unpublished"]],
            [4001, 14001, "http_b", ["4001", "--show-unpublished"]],
            [4002, 14999, "http_c", ["4002", "--show-unpublished", "--livereload-port=14999"]]
        ].map do |port, livereload_port, name, options|
            _, log = spawn_preview.call(name, options)
            [port, livereload_port, log]
        end
        previews.each_with_index do |(port, livereload_port, log), index|
            response = nil
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
            loop do
                begin
                    response = request.call(port, "/draft")
                    break if response.code == "200"
                rescue SystemCallError, Timeout::Error, EOFError
                    # Startup has not bound the HTTP port yet.
                end
                check(Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline,
                      "Preview did not become ready:\n#{File.read(log)}")
                sleep 0.1
            end
            check(response.body.include?("Draft body.") && !response.body.include?("<time"),
                  "HTTP preview omitted the missing-field draft or added publication metadata")
            check(response.body.include?(":#{livereload_port}/livereload.js"), "Wrong LiveReload port in browser script")
            check(request.call(livereload_port, "/livereload.js").code == "200", "LiveReload asset server is unavailable")
            next unless index.zero?

            preview_index = request.call(port, "/").body
            check_home(preview_index)
            random_response = request.call(port, "/haiku/random")
            # Jekyll's development server injects a nonvisual LiveReload script.
            preview_random = random_response.body.sub(/<script>\s*document\.write\(.*?livereload\.js.*?<\/script>/m, "")
            check(random_response.code == "200" && random_response["location"].nil? &&
                  random_targets(preview_random) == [],
                  "Draft preview must serve random page without draft targets")
            check(request.call(port, "/haiku/random.html").body == random_response.body,
                  "Random slashless route must match its HTML backing")
            %w[haiku story].each do |route|
                bare = request.call(port, "/#{route}")
                check(bare.code == "301" && URI(bare["location"]).path == "/#{route}/",
                      "Directory parent must have only its native slash redirect: #{route}")
                parent = request.call(port, "/#{route}/")
                check(parent.code == "200" && parent["location"].nil? &&
                      parent["content-type"].include?("text/html") &&
                      parent.body.include?("rel=\"canonical\" href=\"http://127.0.0.2:3999/#{route}\"") &&
                      parent.body == request.call(port, "/#{route}.html").body &&
                      parent.body == request.call(port, "/#{route}/index.html").body &&
                      !parent.body.include?("Index of /"),
                      "Parent directory must serve the canonical page, not a listing/404/loop: #{route}")
            end
            check(request.call(port, "/story/").body.include?('href="/story/served"'),
                  "Parent story page must link to its published child")
            urls.each_value do |path|
                response = request.call(port, path)
                check(response.code == "200" && response["location"].nil? &&
                      response["content-type"].include?("text/html"),
                      "Slashless URL did not directly serve HTML: #{path}")
                canonical = response.body[/rel="canonical" href="([^"]+)"/, 1]
                check(canonical && URI(canonical).path == path,
                      "Clean URL canonical is incorrect: #{path}")
                backing = request.call(port, "#{path}.html")
                check(backing.code == "200" && backing["content-type"].include?("text/html") &&
                      backing.body == response.body,
                      "Slashless URL does not match its HTML backing file: #{path}")
                trailing = request.call(port, "#{path}/")
                check(trailing.code == "200" && trailing["location"].nil? && trailing.body == response.body,
                      "Incoming trailing slash must serve the canonical content for normalization: #{path}")
            end
            check(request.call(port, "/content/haiku/nested/haiku1.md").code == "404",
                  "Raw content Markdown leaked through preview")
        end
    ensure
        pids.each do |pid|
            begin
                Process.kill("TERM", pid)
            rescue Errno::ESRCH
                # It already exited; wait still reaps our child.
            end
            Process.wait(pid)
        end
        collision_listener.close
    end
    destinations.each { |destination| FileUtils.rm_rf(destination) }
    logs.each { |log| File.unlink(log) }
    File.unlink(served_story)
    puts "PASS: owned LiveReload collision fails visibly; parallel HTTP/draft previews use derived and explicit LiveReload ports"
    published_names = fixtures.keys - %w[draft explicit-draft haiku/draft]
    published_names.each do |name|
        publication(publisher, [File.join(source, "content", "#{name}.md")], source)
    end
    # Rebuilding must remove stale prefix output and directory-index routes.
    FileUtils.mkdir_p(File.join(source, "_site/writing/prose"))
    File.write(File.join(source, "_site/writing/index.html"), "Stale index")
    File.write(File.join(source, "_site/writing/prose/index.html"), "Stale prose")
    FileUtils.mkdir_p(File.join(source, "_site/haiku/haiku1"))
    File.write(File.join(source, "_site/haiku/haiku1/index.html"), "Stale directory index")
    output = build(source)
    index = File.read(File.join(output, "index.html"))
    prose = File.read(File.join(output, "prose.html"))
    poem = File.read(File.join(output, "poem.html"))

    # Random targets follow source membership, publication, and generated URLs.
    random = File.read(random_path)
    random_title = frontmatter(structural_source)["title"]
    random_title = YAML.safe_load(original_config).fetch("title") if random_title.to_s.empty?
    check(random.include?("<title>#{CGI.escapeHTML(random_title)}</title>"),
          "Random document title must match frontmatter or the shared site-title fallback")
    expected_targets = published_names.select { |name| name.start_with?("haiku/") }.map { |name| urls.fetch(name) }
    check(random_targets(random).sort == expected_targets.sort, "Random page targets differ from published source haikus")
    check(!File.exist?(File.join(output, "haiku/random")), "Random route must use HTML backing")
    build(source, "baseurl" => "/preview", "unpublished" => true)
    prefixed = File.read(random_path)
    check(random_targets(prefixed).sort == expected_targets.map { |url| "/preview#{url}" }.sort &&
          prefixed.include?('src="/preview/assets/js/random-haiku.js"'),
          "Baseurl/draft preview changed random membership or omitted URL prefix")
    output = build(source)

    # Check the home copyright, content URLs, layouts, and shared shell independently.
    check(!File.exist?(File.join(output, "writing")), "Stale writing-prefix output survived rebuild")
    check(!index.include?('href="/writing/'), "Index contains a writing-prefix link")
    check_home(index)
    check(index.include?('rel="canonical" href="https://pelgish.ink/"'), "Root canonical must retain its slash")
    check(!File.exist?(File.join(output, "content")) && !index.include?('href="/content/'),
          "Content-prefix output leaked")
    published_names.each do |name|
        html = File.read(output_path.call(output, name))
        check(html.include?("href=\"https://pelgish.ink#{urls.fetch(name)}\""),
              "Canonical URL incorrect: #{name}")
        check(!html.include?("All writing") && !html.include?("<footer"), "Empty writing footer survived")
        check(!html.include?("All content on this site is copyright(c)"), "Home copyright leaked into writing: #{name}")
        check(!html.include?('class="home-page"') && !html.include?('class="home-copyright"'),
              "Home viewport layout leaked into writing: #{name}")
        route = File.join(output, urls.fetch(name).delete_prefix("/"))
        check(!File.exist?(route), "Extensionless artifact or directory route leaked: #{name}")
        check(!html.include?("Published") && !html.include?("<time") && !html.include?("published-time"),
              "Writing shows an automatic publication date: #{name}")
        check(!html.include?('class="kind"') && !html.match?(/>\s*(Poetry|Prose)\s*</),
              "Writing shows an automatic type label: #{name}")
    end
    check(!File.exist?(File.join(output, "stable.html")), "Override retained the default route")
    check(prose.include?('<article class="writing prose">'), "Prose layout missing")
    check(!prose.include?("<h1>A &amp; B</h1>"), "Frontmatter title became a prose heading")
    check(prose.scan(/<h1\b/).length == 1 && prose.include?(">Authored heading</h1>"),
          "Prose must retain only the Markdown-authored heading")
    check(prose.include?("<title>A &amp; B</title>"), "Document title must match escaped frontmatter without a suffix")
    check(prose.include?("<p>Paragraph one.</p>") && prose.include?("<p>Paragraph two.</p>"), "Prose paragraphs missing")
    check(poem.include?('<article class="writing poetry">'), "Poetry layout missing")
    check(!poem.match?(/<h1\b/), "Frontmatter title became a poetry heading")
    check(poem.include?("<title>Verse fixture</title>"), "Poetry document title missing")
    untitled = File.read(output_path.call(output, "haiku/20260620-001"))
    check(untitled.include?("<title>pelgish.ink</title>"), "Untitled document must fall back to the site title")
    check(untitled.include?("<p>Untitled fixture body.</p>"), "Untitled haiku content missing")
    check(!untitled.match?(/<h1\b[^>]*>\s*\S.*?<\/h1>/m), "Untitled haiku gained an automatic heading")
    check(poem.include?('data-appearance="dark"'), "Explicit ink appearance hint missing")
    check(!prose.include?("data-appearance="), "Default must allow the system appearance")
    stable = File.read(File.join(output, "custom/path.html"))
    check(stable.include?('data-appearance="light"'), "Explicit paper appearance hint missing")
    [index, prose, poem, stable].each do |html|
        check(html.include?('data-color-scheme="grapevine"'), "Default/explicit palette hook missing")
        check(html.include?('href="https://fonts.googleapis.com/css2?family=Cantarell:ital,wght@0,400;0,700;1,400&amp;family=Fondamento&amp;display=swap"'),
              "Official font stylesheet or requested styles missing")
        check(html.include?('id="appearance-toggle" class="icon-control" type="button" hidden'), "Toggle must start hidden without JS")
        header = html[/<header class="site-header">(.*?)<\/header>/m, 1]
        check(header && header.scan(/<a\b/).length == 1 && !header.include?("<nav") &&
              header.include?('class="site-title" href="/"'), "Header must retain only the title home link and appearance control")
        %w[moon sun].each do |icon|
            check(html.include?("<span class=\"control-icon appearance-#{icon}\" aria-hidden=\"true\"></span>"),
                  "Decorative #{icon} icon missing")
        end
        check(!html.match?(/Font Awesome|fontawesome|<svg\b|<path\b/i), "Obsolete icon markup or attribution survived")
        check(!html.include?("All writing") && !html.include?("<footer"), "Writing footer survived")
        check(html.index('src="/assets/js/appearance.js"') < html.index('href="/assets/css/style.css"'),
              "Appearance must initialize before local CSS")
    end
    check(poem.match?(/<p>Line one<br\s*\/?>\s*Line two<\/p>/), "Verse line break missing")
    check(poem.include?("<p>Stanza two.</p>"), "Separate verse stanza missing")
    check(prose.include?('href="/assets/css/style.css"'), "Stylesheet URL incorrect")
    check(prose.include?('href="#main"') && prose.include?('id="main"'), "Skip link target missing")
    check(File.size(File.join(output, "assets/css/style.css")) > 0, "Stylesheet missing")
    check(File.size(File.join(output, "assets/js/appearance.js")) > 0, "Appearance script missing")
    %w[haiku shortstory moon sun arrowcircle].each do |icon|
        asset = "assets/images/icon_#{icon}.png"
        check(File.binread(File.join(output, asset)) == File.binread(File.join(root, asset)),
              "Original #{icon} icon was altered or not built")
    end
    check(Dir.glob(File.join(output, "**/*:sec.endpointdlp")).empty?, "Image sidecars must not be published")
    check(File.read(File.join(output, "CNAME")).strip == "pelgish.ink", "Custom domain missing")
    %w[draft explicit-draft haiku/draft].each do |name|
        check(!File.exist?(output_path.call(output, name)), "Draft page leaked: #{name}")
    end
    check(File.binread(structural_source) == structural_bytes, "Structural reader was edited by publication tests")

    # Unpublication deletes persisted fields and removes an already-built public URL.
    path = File.join(source, "content/prose.md")
    publication(publisher, ["--unpublish", path], source)
    check(File.read(path) == fixtures["prose"], "Unpublish retained publication fields")
    output = build(source)
    check(!File.exist?(File.join(output, "prose.html")), "Unpublished URL survived rebuild")

    # Native opt-in works without the publication CLI or a stored timestamp.
    path = File.join(source, "content/haiku/manual.md")
    File.write(path, "---\ntitle: Manual opt-in\npublished: true\n---\nManual body.\n")
    output = build(source)
    html = File.read(File.join(output, "haiku/manual.html"))
    check(html.include?("Manual body.") && !html.include?("<time"), "Manual publication did not work")
    check(html.include?('rel="canonical" href="https://pelgish.ink/haiku/manual"'), "Manual publication canonical missing")
    check_home(File.read(File.join(output, "index.html")))

    # Unpublishing an override retains its metadata/body and removes its custom URL.
    path = File.join(source, "content/stable.md")
    publication(publisher, ["--unpublish", path], source)
    check(File.read(path) == fixtures["stable"], "Unpublish changed native permalink or body")
    output = build(source)
    check(!File.exist?(File.join(output, "custom/path.html")), "Unpublished override survived rebuild")

    # Unsupported palettes must fail explicitly instead of emitting unstyled pages.
    invalid_scheme = File.join(source, "content/unknown-scheme.md")
    File.write(invalid_scheme, "---\npublished: true\ncolor_scheme: unknown\n---\nBody.\n")
    begin
        build(source)
        raise "Unknown palette was accepted"
    rescue Jekyll::Errors::FatalException => error
        check(error.message.include?("Unknown color_scheme") && error.message.include?("grapevine"),
              "Missing actionable palette error")
    ensure
        File.unlink(invalid_scheme)
    end

    # Reserved route aliases must fail instead of silently overwriting the reader.
    collision = File.join(source, "content/haiku/collision.md")
    ["/haiku/random", "/haiku/random.html", "/haiku/random/", "/haiku/random/index.html"].each do |permalink|
        File.write(collision, "---\npublished: true\npermalink: #{permalink}\n---\nCollision.\n")
        begin
            build(source)
            raise "Reserved random route was overwritten"
        rescue Jekyll::Errors::FatalException => error
            check(error.message.include?("/haiku/random is reserved"), "Missing reserved-route error")
        ensure
            File.unlink(collision)
        end
    end
    ["haiku/random", "haiku/random.html", "haiku/random/index.html"].each do |relative_path|
        collision = File.join(source, relative_path)
        FileUtils.mkdir_p(File.dirname(collision))
        File.write(collision, "Static collision")
        begin
            build(source)
            raise "Static file occupied reserved random route"
        rescue Jekyll::Errors::FatalException => error
            check(error.message.include?("/haiku/random is reserved"), "Missing static collision error")
        ensure
            File.unlink(collision)
            FileUtils.rmdir(File.dirname(collision)) if relative_path.end_with?("/index.html")
        end
    end

    # Bare Markdown must fail clearly rather than copying a draft as a public asset.
    File.write(File.join(source, "content/bare.md"), "Private draft without frontmatter\n")
    begin
        build(source)
        raise "Bare Markdown was copied publicly"
    rescue Jekyll::Errors::FatalException => error
        check(error.message.include?("content/bare.md") && error.message.include?("frontmatter"),
              "Missing actionable frontmatter error")
    end
end

puts "PASS: shared-shell random reader, status/no-JS host, underscore discovery, published-only targets, route collisions, home copyright, prose, verse, themes, URLs, canonicals, assets, CNAME, drafts, and raw Markdown protection"

# Verify the actual palette tokens against WCAG text/control contrast thresholds.
css = File.read(File.join(root, "assets/css/style.css"))
colors = css.scan(/--([\w-]+):\s*(#[0-9A-Fa-f]{6});/).to_h
luminance = lambda do |hex|
    channels = hex.delete_prefix("#").scan(/../).map do |channel|
        value = channel.to_i(16) / 255.0
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    channels.zip([0.2126, 0.7152, 0.0722]).sum { |value, weight| value * weight }
end
["", "dark-"].each do |prefix|
    background = luminance.call(colors.fetch("#{prefix}background"))
    %w[foreground heading muted link accent-link rule].each do |role|
        foreground = luminance.call(colors.fetch(role == "rule" ? role : "#{prefix}#{role}"))
        contrast = ([background, foreground].max + 0.05) / ([background, foreground].min + 0.05)
        check(contrast >= (role == "rule" ? 3 : 4.5), "#{prefix}#{role} contrast too low: #{contrast.round(2)}")
        puts "Contrast #{prefix}#{role}: #{contrast.round(2)}:1"
    end
end
puts "PASS: grapevine light/dark normal text, links, muted text, headings, focus colors, and rules"
