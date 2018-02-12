defmodule Membrane.Element.HTTPoison.Mixfile do
  use Mix.Project

  def project do
    [app: :membrane_element_httpoison,
     compilers: Mix.compilers,
     version: "0.0.1",
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     description: "Membrane Multimedia Framework (HTTPoison Element)",
     maintainers: ["Marcin Lewandowski"],
     licenses: ["MIT"],
     name: "Membrane Element: HTTPoison",
     source_url: "httpoisons://bitbucket.org/radiokit/membrane-element-httpoison",
     preferred_cli_env: [espec: :test],
     deps: deps()]
  end


  def application do
    [applications: [
      :membrane_core,
      :httpoison
    ], mod: {Membrane.Element.HTTPoison, []}]
  end


  defp elixirc_paths(:test), do: ["lib", "spec/support"]
  defp elixirc_paths(_),     do: ["lib",]


  defp deps do
    [
      {:membrane_core, git: "git@github.com:membraneframework/membrane-core.git"},
      {:httpoison, "~> 1.0.0"},
    ]
  end
end
