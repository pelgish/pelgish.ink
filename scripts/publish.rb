# Edit only publication metadata, retaining Markdown bytes and ordinary YAML formatting.
require "yaml"
require "date"
require "time"
require "tempfile"

PUBLICATION_KEYS = %w[published published_timestamp].freeze
USAGE = "Usage: publish.sh [--unpublish] PATH.md (flag may also follow path)".freeze

# Load YAML as data only; dates and timestamps are standard frontmatter values.
def metadata(yaml)
    YAML.safe_load(yaml, permitted_classes: [Date, Time], aliases: true)
end

# Validate the entire document before preparing an atomic replacement.
def publish(path, unpublish)
    raise ArgumentError, "expected an existing .md or .markdown regular file" unless
        %w[.md .markdown].include?(File.extname(path).downcase) && File.file?(path) && !File.symlink?(path)

    original = File.binread(path)
    text = original.dup.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "expected UTF-8 Markdown" unless text.valid_encoding?

    match = /\A---\r?\n(?<yaml>.*?)^---[ \t]*(?:\r?\n|\z)/m.match(text)
    raise ArgumentError, "missing YAML frontmatter delimiters" unless match

    yaml = match[:yaml]
    stream = YAML.parse_stream(yaml)
    mapping = stream.children.first&.root
    raise ArgumentError, "frontmatter must be one YAML mapping" unless
        stream.children.size == 1 && mapping.is_a?(Psych::Nodes::Mapping)

    pairs = mapping.children.each_slice(2).to_a
    fields = pairs.select { |key, _| key.is_a?(Psych::Nodes::Scalar) && PUBLICATION_KEYS.include?(key.value) }
    raise ArgumentError, "duplicate publication keys" unless fields.map { |key, _| key.value }.uniq.size == fields.size

    data = metadata(yaml)
    raise ArgumentError, "frontmatter must be a YAML mapping" unless data.is_a?(Hash)
    raise ArgumentError, "publication keys must not be inherited through YAML merges" if
        PUBLICATION_KEYS.any? { |key| data.key?(key) && fields.none? { |node, _| node.value == key } }

    desired = data.reject { |key, _| PUBLICATION_KEYS.include?(key) }
    unless unpublish
        desired["published"] = true
        desired["published_timestamp"] = Time.now.utc.iso8601
    end

    # Block mappings keep every unrelated line, including comments and scalar styles.
    # Flow mappings are normalized by YAML's emitter, never by text substitutions.
    newline = match[0].start_with?("---\r\n") ? "\r\n" : "\n"
    if mapping.style == Psych::Nodes::Mapping::FLOW || pairs.any? { |key, _| key.start_column != 0 }
        updated = YAML.dump(desired).sub(/\A---\n/, "").gsub("\n", newline)
    else
        lines = yaml.lines
        fields.each do |key, value|
            last = value.end_line + (value.end_column.positive? ? 1 : 0)
            (key.start_line...last).each { |line| lines[line] = "" }
        end
        additions = unpublish ? "" : "published: true#{newline}published_timestamp: \"#{desired['published_timestamp']}\"#{newline}"
        lines.insert(mapping.end_line, additions)
        updated = lines.join
    end

    # Detect alias/anchor dependencies or unusual YAML that cannot be edited safely.
    raise ArgumentError, "cannot safely edit this frontmatter representation" unless metadata(updated) == desired
    replacement = text[0...match.begin(:yaml)] + updated + text[match.end(:yaml)..]
    return if replacement.b == original

    # The temporary file is in the target directory; rename cannot expose partial data.
    # Tempfile's ensure cleanup also covers validation/write failures.
    mode = File.stat(path).mode & 0o7777
    Tempfile.create([".publish-", ".tmp"], File.dirname(File.expand_path(path))) do |file|
        file.binmode
        file.write(replacement.b)
        file.flush
        file.fsync
        file.chmod(mode)
        File.rename(file.path, path)
    end
end

begin
    arguments = ARGV.dup
    unpublish = arguments.delete("--unpublish")
    raise ArgumentError, USAGE if ARGV.count("--unpublish") > 1 || arguments.size != 1 ||
        arguments.first.empty? || arguments.first.start_with?("-")

    publish(arguments.first, unpublish)
    puts "publish.sh: #{unpublish ? 'unpublished' : 'published'} #{arguments.first}"
rescue ArgumentError, Psych::Exception, SystemCallError, IOError => error
    warn "publish.sh: #{error.message}"
    exit 1
end
