# Claude guide

This repository is a fork of [tbook/luanti-villages](https://github.com/tbook/luanti-villages), which
aims to make villager professions richer, starting with the farmer. `upstream` is that repository and
`origin` is the fork. Open pull requests against the fork's `main`, never upstream.

Read [`AGENTS.md`](AGENTS.md) for the code map, testing and conventions. It applies here too.

`lua5.1` may not be installed. `luajit` runs the tests the same way:

```sh
for t in tests/*.lua; do luajit "$t"; done
```
