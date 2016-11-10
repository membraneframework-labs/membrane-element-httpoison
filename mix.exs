defmodule Membrane.Element.HTTP.Mixhttp do
  use Mix.Project

  def project do
    [app: :membrane_element_http,
     compilers: Mix.compilers,
     version: "0.0.1",
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     description: "Membrane Multimedia Framework (HTTP Element)",
     maintainers: ["Marcin Lewandowski"],
     licenses: ["LGPL"],
     name: "Membrane Element: HTTP",
     source_url: "https://bitbucket.org/radiokit/membrane-element-http",
     preferred_cli_env: [espec: :test],
     deps: deps]
  end


  def application do
    [applications: [
      :membrane_core,
      :httpoison
    ], mod: {Membrane.Element.HTTP, []}]
  end


  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib",]


  defp deps do
    [
      {:membrane_core, git: "git@bitbucket.org:radiokit/membrane-core.git"},
      {:httpoison, "~> 0.10.0"},
    ]
  end
end
