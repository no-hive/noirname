# NoirName Mintlify docs

Four pages: About, Architecture, Guides (starting with Contribute), and Changelog. `docs.json` defines their order. Put this directory's contents at the root of a Mintlify documentation repository.

To preview locally, install the Mintlify CLI (`npm i -g mint`) and run `mint dev` from this directory. Connect the repository to Mintlify to publish on push.

## Changelog automation contract

A future GitHub Actions workflow can insert entries between `CHANGELOG_ENTRIES_START` and `CHANGELOG_ENTRIES_END` in `changelog.mdx`. Keep newest entries first. Use one block per published change:

```mdx
<Update label="2026-09-28" description="v0.1.0">
  - Short, user-facing change. [Release](https://github.com/no-hive/noirname/releases/tag/v0.1.0)
</Update>
```

Use an ISO date in `label`, a unique version or release identifier in `description`, and a link to the release or merged PR. Generate text from reviewed release notes rather than raw commit messages. An automation should check for an existing identifier before inserting, so reruns do not duplicate entries. The placeholder sentence can be removed when the first entry is published.

The architecture summary supplied for this draft refers to `noirname-demo.html` and `main_5_.nr` as implementation references. They were not included in the supplied files, so verify contract details against the repository before treating this overview as an API specification.
