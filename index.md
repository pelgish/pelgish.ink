---
layout: default
title: pelgish.ink
permalink: /
---

<section class="home-controls" aria-label="Explore writing">
    <a class="icon-control" href="{{ '/story' | relative_url }}" aria-label="Short Stories" title="Read short stories">
        <span class="control-icon icon-shortstory" aria-hidden="true"></span>
        <span>Short Stories</span>
    </a>
    <a class="icon-control" href="{{ '/haiku' | relative_url }}" aria-label="Haikus" title="Read haikus">
        <span class="control-icon icon-haiku" aria-hidden="true"></span>
        <span>Haikus</span>
    </a>
</section>

{% assign copyright_start_year = site.copyright_start_year | default: 2026 | append: "" %}
{% assign copyright_end_year = site.time | date: "%Y" %}
<section class="home-copyright" aria-label="Copyright">
    <p>All content on this site is copyright(c) Connor Shugg {{ copyright_start_year }}{% if copyright_start_year != copyright_end_year %}-{{ copyright_end_year }}{% endif %}. All rights reserved.</p>
    <p>For inquiries, permissions, etc., please <a href="/legal">click here</a>.</p>
</section>
