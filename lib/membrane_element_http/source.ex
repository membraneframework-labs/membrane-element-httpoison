defmodule Membrane.Element.HTTPoison.Source do
  use Membrane.Element.Base.Source
  use Membrane.Mixins.Log
  alias Membrane.Element.HTTPoison.Source.Options


  def_known_source_pads %{
    :source => {:always, :any}
  }


  # Private API

  @doc false
  def handle_init(%Options{method: method, location: location, headers: headers, body: body, options: options}) do
    {:ok, %{
      location: location,
      method: method,
      headers: headers,
      body: body,
      options: options,
      ref: nil,
    }}
  end


  @doc false
  def handle_play(%{method: method, location: location, body: body, headers: headers, options: options} = state) do
    case HTTPoison.request(method, location, body, headers, options ++ [stream_to: self()]) do
      {:ok, %HTTPoison.AsyncResponse{id: ref}} ->
        {:ok, %{state | ref: ref}}

      {:error, reason} ->
        {:error, {:httperror, reason}}
    end
  end


  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: 200}, state) do
    debug("Got 200 OK")
    {:ok, state}
  end

  def handle_other(%HTTPoison.AsyncStatus{code: code}, state) do
    warn("Got unexpected status code #{code}")
    {:error, {:code, code}, state}
  end

@doc false
  def handle_other(%HTTPoison.AsyncHeaders{headers: headers}, state) do
    debug("Got headers #{inspect(headers)}")
    {:ok, state}
  end

  def handle_other(%HTTPoison.AsyncChunk{chunk: chunk}, state) do
    debug("Got chunk #{inspect(chunk)}")

    {:ok, [{:send, {:source, %Membrane.Buffer{payload: chunk}}}], state}
  end

  def handle_other(%HTTPoison.AsyncEnd{}, state) do
    debug("End of stream")

    {:ok, [{:send, {:source, Membrane.Event.eos()}}], state}
  end

  def handle_other(%HTTPoison.AsyncRedirect{headers: headers}, state) do
    case headers |> List.keyfind("Location", 0) do
      {"Location", new_location} ->
        debug("Redirect to #{new_location}")

      _ ->
        warn("Got redirect but without specyfying location")
    end

    {:ok, state}
  end
end
