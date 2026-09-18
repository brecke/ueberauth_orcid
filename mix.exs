defmodule UeberauthOrcid.MixProject do
  use Mix.Project

  @source_url "https://github.com/brecke/ueberauth_orcid"
  @version "0.2.5"

  def project do
    [
      app: :ueberauth_orcid,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_local_path: "priv/plts", plt_core_path: "priv/plts"],
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
      source_ref: System.get_env("SOURCE_REF") || @version,
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
      {:oauth2, "~> 2.1 and >= 2.1.1"},
      {:jason, "~> 1.4"},
      {:ueberauth, "~> 0.10.8"},
      {:plug, "~> 1.16.6 or ~> 1.17.4 or ~> 1.18.5 or ~> 1.19.5 or >= 1.20.3 and < 2.0.0"},
      {:tesla, ">= 1.18.3 and < 2.0.0"},
      {:credo, "~> 1.7.19", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4.8", only: :dev, runtime: false},
      {:sobelow, "~> 0.15.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.36.1", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description: "An Ueberauth strategy for using Orcid to authenticate your users via OAuth2.",
      files: ["lib", "mix.exs", "README.md", "CONTRIBUTING.md", "LICENSE", "SECURITY.md"],
      maintainers: ["Miguel Laginha"],
      licenses: ["MIT"],
      links: %{
        GitHub: @source_url
      }
    ]
  end
end
