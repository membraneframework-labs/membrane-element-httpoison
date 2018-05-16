# Membrane Multimedia Framework: HTTPoison Element

This package provides elements that can be used to read files over HTTP using
[HTTPoison](https://github.com/edgurgel/httpoison) library.

# Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_element_httpoison, git: "git@github.com:membraneframework/membrane-element-httpoison.git"}
```

# Sample usage

This should get you a kitten from imgur and save as `kitty.jpg`.

```elixir
defmodule HTTPoison.Pipeline do
  use Membrane.Pipeline
  alias Pipeline.Spec
  alias Membrane.Element.File
  alias Membrane.Element.HTTPoison

  @impl true
  def handle_init(_) do
    children = [
      file_src: %HTTPoison.Source{location: "http://i.imgur.com/z4d4kWk.jpg"},
      file_sink: %File.Sink{location: "kitty.jpg"},
    ]
    links = %{
      {:file_src, :source} => {:file_sink, :sink}
    }

    {{:ok, %Spec{children: children, links: links}}, %{}}
  end
end
```