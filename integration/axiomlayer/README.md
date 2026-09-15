# AxiomLayer SQLite integration

SQLite is Fossil-first. The canonical repositories are the SQLite project's
Fossil repositories, led by <https://sqlite.org/src>. The SQLite project names
<https://github.com/sqlite/sqlite> as its official, hourly, read-only Git
mirror. `AxiomLayer/sqlite` is a true GitHub fork of that official mirror; it is
an integration boundary, not a replacement for the Fossil urtext.

The organization repository's final name is **`AxiomLayer/sqlite`**. The
provisional `AxiomLayer/sqlite-provenance` name and `provenance-mirror`
acquisition mode in the dotfiles promotion drafts are superseded. Their
replacement is `github-fork-of-official-git-mirror`, while the canonical
authority remains `https://sqlite.org/src`. Organization policy may name
`sqlite` for future immutable-release enforcement, although this integration
does not create releases.

`runtime-pin.json` records both identity systems on purpose. GitHub automation
uses full Git commit IDs, while SQLite provenance uses the corresponding
`manifest.uuid` Fossil IDs. The fleet release remains SQLite 3.53.4 / build
3530400 from sqlite.org. Its source archive keeps SQLite's published SHA3-256
and an independently verified SHA-256 suitable for a Nix fixed-output source.
For that release the mapping is Git commit
`b09c88c14082339b66c7b7158d609a771e64ca69` to Fossil ID
`bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`;
the same Fossil ID is embedded in the archive's `SQLITE_SOURCE_ID`.

The integration workflow is build/test-only and has read-only repository
permissions. It never publishes a release, accepts a publisher credential, or
uses an environment. It proves all of the following:

- the exact fleet source archive still matches both recorded digests;
- the release archive's `SQLITE_SOURCE_ID` binds it to the recorded Fossil ID;
- the full-SHA-pinned release mirror has the same version and Fossil ID;
- the full-SHA-pinned AxiomLayer candidate passes SQLite's `verify-source`;
- both sources build under locked Nix inputs with `ENABLE_FTS5`;
- both CLIs create, populate, and query a real FTS5 virtual table; and
- hosted Python dynamically loads each built library and passes the same probe.

Every six hours, the default-branch workflow checks the official mirror. If it
advanced, CI tests that exact newly observed 40-character Git commit through
the same Nix candidate package without rewriting the lock. A compatible drift
still leaves the scheduled check red until a reviewed pin-update PR records the
new Git and Fossil identities. This makes upstream movement visible without
granting CI write or publish authority.

## Dotfiles promotion follow-up

The dotfiles #49 worktree is intentionally outside this branch. Its minimal
reconciliation is:

1. In `config/upstream-promotion-policy.json`, change SQLite's `acquisition` to
   `fork` and `repository` to `AxiomLayer/sqlite`; keep `upstream` as
   `sqlite.org/source`, keep version `3.53.4` and Git commit
   `b09c88c14082339b66c7b7158d609a771e64ca69`, and add `gitMirror` =
   `sqlite/sqlite` plus `fossilManifestUuid` =
   `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`.
2. Permit those two provenance fields in the policy schema, require their exact
   shapes for `id = sqlite`, and reject them on other source entries.
3. Extend `SourcePolicy` and `validatePolicy()` with the same SQLite-only tuple;
   remove the `provenance-mirror` acquisition exception.
4. Rename the SQLite repository in `promotion/candidate.json`, then recompute
   its `policySha256`. The source version and Git commit do not change.
5. Update `test/upstream-promotion_test.ts` and
   `docs/UPSTREAM-PROMOTION.md` to assert and explain the Fossil → official Git
   mirror → AxiomLayer fork chain.

No runtime artifact URL or digest changes as a consequence. Dotfiles #51
correctly uses the final repository name `sqlite` for future immutable-release
policy.
