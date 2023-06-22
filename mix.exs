defmodule UeberauthOrcid.MixProject do
  use Mix.Project

  def project do
    [
      app: :ueberauth_orcid,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
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
      {:oauth2, "~> 1.0 or ~> 2.0"},
      {:ueberauth, "~> 0.7"}
    ]
  end

  defp package do
    [
      description: "An Ueberauth strategy for using Orcid to authenticate your users.",
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Miguel Laginha"],
      licenses: ["MIT"],
    ]
  end

end
