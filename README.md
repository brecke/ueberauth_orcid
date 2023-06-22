# UeberauthOrcid

Orcid integration for Ueberauth (oauth2 authentication)

This was heavily inspired by the github official Ueberauth plugin.

Feel free to get in touch if you need help using this!

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ueberauth_orcid` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ueberauth_orcid, git: "https://github.com/brecke/ueberauth_orcid", tag: "0.2.2"}
  ]
end
```

and add it to the `extra_applications` too:

```elixir
def application do
[
  mod: {Benchlight.Application, []},
  extra_applications: [:logger, :runtime_tools, :ueberauth_orcid]
]
end

```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ueberauth_orcid>.
