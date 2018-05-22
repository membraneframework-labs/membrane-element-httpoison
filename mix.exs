defmodule Membrane.Element.HTTPoison.Mixfile do
  use Mix.Project

  def project do
    [
      app: :membrane_element_httpoison,
      compilers: Mix.compilers(),
      version: "0.0.1",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Membrane Multimedia Framework (HTTPoison Element)",
      package: package(),
      name: "Membrane Element: HTTPoison",
      source_url: "http://github.com/membraneframework/membrane-element-httpoison",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [],
      mod: {Membrane.Element.HTTPoison, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "spec/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:membrane_core, git: "git@github.com:membraneframework/membrane-core.git"},
      {:mockery, "~> 2.1", runtime: false},
      {:httpoison, "~> 1.1.0"}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"]
    ]
  end
end
