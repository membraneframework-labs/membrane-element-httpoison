defmodule Membrane.Element.HTTPoison.Mixfile do
  use Mix.Project

  @version "0.2.0"
  @github_url "http://github.com/membraneframework/membrane-element-httpoison"

  def project do
    [
      app: :membrane_element_httpoison,
      compilers: Mix.compilers(),
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Membrane Multimedia Framework (HTTPoison Element)",
      package: package(),
      name: "Membrane Element: HTTPoison",
      source_url: @github_url,
      docs: docs(),
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

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:mockery, "~> 2.1", runtime: false},
      {:membrane_core, "~> 0.2.0"},
      {:httpoison, "~> 1.1"}
    ]
  end
end
