defmodule UeberauthOrcid.MixProject do
  use Mix.Project

  @source_url "https://github.com/brecke/ueberauth_orcid"
  @version "0.2.2"

  def project do
    [
      app: :ueberauth_orcid,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  defp docs do
    [
      extras: [
        "CONTRIBUTING.md": [title: "Contributing"],
        LICENSE: [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "#v{@version}",
      formatters: ["html"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ueberauth, :oauth2]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:oauth2, "~> 2.0"},
      {:ueberauth, "~> 0.10"},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description: "An Ueberauth strategy for using Orcid to authenticate your users via OAuth2.",
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Miguel Laginha"],
      licenses: ["MIT"],
      links: %{
        Changelog: "https://hexdocs.pm/ueberauth_orcid/changelog.html",
        GitHub: @source_url
      }
    ]
  end
end
