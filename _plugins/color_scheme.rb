# Validate page palettes before emitting the shared shell.
module ColorSchemeFilter
    # Extend this list alongside the corresponding CSS palette, not the layouts.
    def validated_color_scheme(scheme)
        return scheme if scheme == "grapevine"

        raise Jekyll::Errors::FatalException,
              "Unknown color_scheme #{scheme.inspect}; supported color_scheme: grapevine"
    end
end

Liquid::Template.register_filter(ColorSchemeFilter)
