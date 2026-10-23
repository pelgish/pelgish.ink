---
layout: default
title: Home
permalink: /
---

{% assign copyright_start_year = site.copyright_start_year | default: 2026 | append: "" %}
{% assign copyright_end_year = site.time | date: "%Y" %}
<section aria-label="Copyright">
    <p>All content here is copyright(c) Connor Shugg {{ copyright_start_year }}{% if copyright_start_year != copyright_end_year %}-{{ copyright_end_year }}{% endif %}</p>
</section>
