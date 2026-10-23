# [pelgish.ink](https://pelgish.ink)

Connor's creative writing website.

## Local setup and preview

```sh
./scripts/setup-dependencies.sh
./scripts/serve.sh
```

If system prerequisites are missing, setup lists them and exits without system changes.
On Debian/Ubuntu, explicitly opt in to installing them with:

```sh
./scripts/setup-dependencies.sh --install-system-dependencies
```

For the same production build and regression check used in CI:

```sh
./scripts/bundle.sh exec ruby scripts/check.rb
JEKYLL_ENV=production ./scripts/bundle.sh exec jekyll build --trace
```

</details>

