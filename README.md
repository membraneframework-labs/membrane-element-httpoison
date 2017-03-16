# Membrane Multimedia Framework: HTTPoison Element

This package provides elements that can be used to read files over HTTP using
[HTTPoison](https://github.com/edgurgel/httpoison) library.

# Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_element_httpoison, git: "git@github.com:membraneframework/membrane-element-httpoison.git"}
```

Then add the following line to your `applications` in `mix.exs`.

```elixir
:membrane_element_httpoison
```

# Sample usage

This should copy `httpoisons://en.wikipedia.org/wiki/Main_Page` to `./test`:

```elixir
{:ok, sink} = Membrane.Element.File.Sink.start_link(%Membrane.Element.File.SinkOptions{location: "./test"})
Membrane.Element.play(sink)

{:ok, source} = Membrane.Element.HTTPoison.Source.start_link(%Membrane.Element.HTTPoison.SourceOptions{location: "httpoisons://en.wikipedia.org/wiki/Main_Page"})
Membrane.Element.link(source, sink)
Membrane.Element.play(source)
```

# Authors

Marcin Lewandowski
