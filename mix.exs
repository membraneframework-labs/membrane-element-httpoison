defmodule Membrane.Element.HTTPoison.Mixfile do
  use Mix.Project

  def project do
    [
      app: :membrane_element_httpoison,
      compilers: Mix.compilers(),
      version: "0.1.0",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Membrane Multimedia Framework (HTTPoison Element)",
      package: package(),
      name: "Membrane Element: HTTPoison",
      source_url: link(),
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

  defp link do
    "http://github.com/membraneframework/membrane-element-httpoison"
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => link(),
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.18", only: :dev, runtime: false},
      {:mockery, "~> 2.1", runtime: false},
      {:membrane_core, "~> 0.1"},
      {:httpoison, "~> 1.1.0"}
    ]
  end
end
