# Membrane Multimedia Framework: HTTP Element

This package provides elements that can be used to read files over HTTP.

# Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_element_http, git: "git@bitbucket.org:radiokit/membrane-element-http.git"}
```

Then add the following line to your `applications` in `mix.exs`.

```elixir
:membrane_element_http
```

# Sample usage

This should copy `https://en.wikipedia.org/wiki/Main_Page` to `./test`:

```elixir
{:ok, sink} = Membrane.Element.File.Sink.start_link(%Membrane.Element.File.SinkOptions{location: "./test"})
Membrane.Element.play(sink)

{:ok, source} = Membrane.Element.HTTP.Source.start_link(%Membrane.Element.HTTP.SourceOptions{location: "https://en.wikipedia.org/wiki/Main_Page"})
Membrane.Element.link(source, sink)
Membrane.Element.play(source)
```

# Authors

Marcin Lewandowski
