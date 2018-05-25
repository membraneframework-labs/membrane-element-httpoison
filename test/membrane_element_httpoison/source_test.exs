defmodule Membrane.Element.HTTPoison.SourceTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use Mockery

  @module Membrane.Element.HTTPoison.Source

  @default_state %{
    body: "",
    headers: [],
    is_live: false,
    location: "url",
    method: :get,
    poison_opts: [],
    resume_on_error: false,
    async_response: nil,
    streaming: false,
    pos_counter: 0,
    playing: false
  }

  @mock_response %HTTPoison.AsyncResponse{id: :ref}

  def state_streaming(_) do
    state =
      @default_state
      |> Map.merge(%{
        streaming: true,
        async_response: @mock_response,
        playing: true
      })

    [state_streaming: state]
  end

  describe "handle_prepare/2 should" do
    test "close request when moving from :playing to :prepared" do
      state = %{@default_state | async_response: @mock_response}
      mock(:hackney, close: 1)
      assert {:ok, new_state} = @module.handle_prepare(:playing, state)
      assert new_state.playing == false
      assert new_state.async_response == nil
      assert_called(:hackney, :close, [:ref])
    end

    test "do nothing when going from :stopped to :prepared" do
      mock(:hackney, close: 1)
      assert @module.handle_prepare(:stopped, @default_state) == {:ok, @default_state}
      refute_called(:hackney, :close)
    end
  end

  test "handle_play/1 should start an async request" do
    mock(HTTPoison, [request: 5], {:ok, @mock_response})

    state =
      @default_state
      |> Map.merge(%{
        headers: [:hd],
        poison_opts: [opt: :some],
        body: "body"
      })

    assert {:ok, new_state} = @module.handle_play(state)
    assert new_state.playing == true
    assert new_state.async_response == @mock_response
    assert new_state.streaming == true

    assert_called(HTTPoison, :request, [
      :get,
      "url",
      "body",
      [:hd],
      [opt: :some, stream_to: _, async: :once]
    ])
  end

  describe "handle_demand/5 should" do
    test "request next chunk if it haven't been already" do
      state = %{@default_state | async_response: @mock_response}
      mock(HTTPoison, [stream_next: 1], {:ok, @mock_response})

      assert {:ok, new_state} = @module.handle_demand(:source, 42, :bytes, nil, state)
      assert new_state.async_response == @mock_response
      assert new_state.streaming == true

      pin_response = @mock_response

      assert_called(HTTPoison, :stream_next, [^pin_response])
    end

    test "return error when stream_next fails" do
      state = %{@default_state | async_response: @mock_response}
      mock(HTTPoison, [stream_next: 1], {:error, :reason})
      mock(:hackney, close: 1)

      assert {{:error, reason}, new_state} =
               @module.handle_demand(:source, 42, :bytes, nil, state)

      assert reason == {:stream_next, :reason}
      assert new_state.async_response == nil
      assert new_state.streaming == false

      pin_response = @mock_response

      assert_called(HTTPoison, :stream_next, [^pin_response])
      assert_called(:hackney, :close, [:ref])
    end

    test "do nothing when next chunk from HTTPoison was requested" do
      state = %{@default_state | streaming: true}
      mock(HTTPoison, [stream_next: 1], {:ok, @mock_response})

      assert @module.handle_demand(:source, 42, :bytes, nil, state) == {:ok, state}
      refute_called(HTTPoison, :stream_next)
    end
  end

  def test_msg_trigger_redemand(msg, state) do
    assert {{:ok, actions}, new_state} = @module.handle_other(msg, state)
    assert actions == [redemand: :source]
    assert new_state.streaming == false
  end

  describe "handle_other/2 for message" do
    setup :state_streaming

    test "async status 200 should trigger redemand with streaming false", %{
      state_streaming: state
    } do
      msg = %HTTPoison.AsyncStatus{code: 200, id: :ref}
      test_msg_trigger_redemand(msg, state)
    end

    test "async status 206 should trigger redemand with streaming false", %{
      state_streaming: state
    } do
      msg = %HTTPoison.AsyncStatus{code: 206, id: :ref}
      test_msg_trigger_redemand(msg, state)
    end

    test "async status 301 should return error and close connection", %{state_streaming: state} do
      msg = %HTTPoison.AsyncStatus{code: 301, id: :ref}
      mock(:hackney, [close: 1], :ok)
      assert {{:error, reason}, new_state} = @module.handle_other(msg, state)
      assert reason == {:httpoison, :redirect}
      assert new_state.streaming == false
      assert new_state.async_response == nil
      assert_called(:hackney, :close, [:ref])
    end

    test "async status 302 should should return error and close connection", %{
      state_streaming: state
    } do
      msg = %HTTPoison.AsyncStatus{code: 302, id: :ref}
      mock(:hackney, [close: 1], :ok)
      assert {{:error, reason}, new_state} = @module.handle_other(msg, state)
      assert reason == {:httpoison, :redirect}
      assert new_state.streaming == false
      assert new_state.async_response == nil
      assert_called(:hackney, :close, [:ref])
    end

    test "async status 416 should should return error and close connection", %{
      state_streaming: state
    } do
      msg = %HTTPoison.AsyncStatus{code: 416, id: :ref}
      mock(:hackney, [close: 1], :ok)
      assert {{:error, reason}, new_state} = @module.handle_other(msg, state)
      assert reason == {:httpoison, :invalid_range}
      assert new_state.streaming == false
      assert new_state.async_response == nil
      assert_called(:hackney, :close, [:ref])
    end

    test "async status with unsupported code should return error and close connection", %{
      state_streaming: state
    } do
      mock(:hackney, [close: 1], :ok)
      codes = [500, 501, 502, 402, 404]

      codes
      |> Enum.each(fn code ->
        msg = %HTTPoison.AsyncStatus{code: code, id: :ref}
        assert {{:error, reason}, new_state} = @module.handle_other(msg, state)
        assert reason == {:http_code, code}
        assert new_state.streaming == false
        assert new_state.async_response == nil
      end)

      assert_called(:hackney, :close, [:ref], [length(codes)])
    end

    test "async headers should trigger redemand with streaming false", %{state_streaming: state} do
      msg = %HTTPoison.AsyncHeaders{headers: [], id: :ref}
      test_msg_trigger_redemand(msg, state)
    end

    test "async chunk when not playing should ignore the data", %{state_streaming: state} do
      state = %{state | playing: false}
      msg = %HTTPoison.AsyncChunk{chunk: <<>>, id: :ref}
      assert {:ok, new_state} = @module.handle_other(msg, state)
      assert new_state.streaming == false
    end

    test "async chunk should produce buffer, update pos_counter and trigger redemand", %{
      state_streaming: state
    } do
      msg = %HTTPoison.AsyncChunk{chunk: <<1, 2, 3>>, id: :ref}
      assert {{:ok, actions}, new_state} = @module.handle_other(msg, state)

      assert [buffer: buf_action, redemand: :source] = actions
      assert buf_action == {:source, %Membrane.Buffer{payload: <<1, 2, 3>>}}

      assert new_state.pos_counter == state.pos_counter + 3
      assert new_state.streaming == false
    end

    test "async end should send EOS event and remove asyn_response from state", %{
      state_streaming: state
    } do
      msg = %HTTPoison.AsyncEnd{id: :ref}
      assert {{:ok, actions}, new_state} = @module.handle_other(msg, state)
      assert actions == [event: {:source, Membrane.Event.eos()}]
      assert new_state.async_response == nil
      assert new_state.streaming == false
    end

    test "HTTPoison error should return error and close request", %{state_streaming: state} do
      mock(:hackney, [close: 1], :ok)
      msg = %HTTPoison.Error{reason: :reason, id: :ref}
      assert {{:error, reason}, new_state} = @module.handle_other(msg, state)
      assert reason == {:httpoison, :reason}
      assert new_state.streaming == false
      assert new_state.async_response == nil
      assert_called(:hackney, :close, [:ref])
    end

    test "async redirect should change location and start create new request", %{
      state_streaming: state
    } do
      second_response = %HTTPoison.AsyncResponse{id: :ref2}
      mock(HTTPoison, [request: 5], {:ok, second_response})

      state =
        state
        |> Map.merge(%{
          headers: [:hd],
          poison_opts: [opt: :some],
          body: "body"
        })

      msg = %HTTPoison.AsyncRedirect{to: "url2", id: :ref}
      assert {:ok, new_state} = @module.handle_other(msg, state)
      assert new_state.location == "url2"
      assert new_state.async_response == second_response
      assert new_state.streaming == true

      assert_called(HTTPoison, :request, [
        :get,
        "url2",
        "body",
        [:hd],
        [opt: :some, stream_to: _, async: :once]
      ])
    end
  end

  def state_resume_not_live(_) do
    state =
      @default_state
      |> Map.merge(%{
        resume_on_error: true,
        async_response: @mock_response,
        pos_counter: 42
      })

    second_response = %HTTPoison.AsyncResponse{id: :ref2}
    expected_headers = [{"Range", "bytes=42-"}]
    [state: state, second_response: second_response, expected_headers: expected_headers]
  end

  def test_reconnect(ctx, tested_call) do
    %{
      second_response: second_response,
      state: state,
      expected_headers: expected_headers
    } = ctx

    mock(HTTPoison, [request: 5], {:ok, ctx.second_response})

    assert {:ok, new_state} = tested_call.(state)
    assert new_state.async_response == second_response
    assert new_state.streaming == true

    assert_called(HTTPoison, :request, [
      :get,
      "url",
      "",
      ^expected_headers,
      [stream_to: _, async: :once]
    ])
  end

  describe "with resume_on_error: true in options" do
    setup :state_resume_not_live

    test "handle_demand should reconnect on error starting from current position", ctx do
      mock(HTTPoison, [stream_next: 1], {:error, :reason})

      test_reconnect(ctx, fn state ->
        @module.handle_demand(:source, 42, :bytes, nil, state)
      end)

      # trick to overcome Mockery limitations
      pin_response = @mock_response
      assert_called(HTTPoison, :stream_next, [^pin_response])
    end

    test "handle_other should reconnect on error starting from current position", ctx do
      test_reconnect(ctx, fn state ->
        msg = %HTTPoison.Error{reason: :reason, id: :ref}
        @module.handle_other(msg, state)
      end)
    end
  end

  def state_resume_live(_) do
    state =
      @default_state
      |> Map.merge(%{
        resume_on_error: true,
        is_live: true,
        async_response: @mock_response,
        pos_counter: 42
      })

    second_response = %HTTPoison.AsyncResponse{id: :ref2}
    [state: state, second_response: second_response, expected_headers: []]
  end

  describe "with resume_on_error: true and is_live: true in options" do
    setup :state_resume_live

    test "handle_demand should reconnect on error", ctx do
      mock(HTTPoison, [stream_next: 1], {:error, :reason})

      test_reconnect(ctx, fn state ->
        @module.handle_demand(:source, 42, :bytes, nil, state)
      end)

      # trick to overcome Mockery limitations
      pin_response = @mock_response
      assert_called(HTTPoison, :stream_next, [^pin_response])
    end

    test "handle_other", ctx do
      test_reconnect(ctx, fn state ->
        msg = %HTTPoison.Error{reason: :reason, id: :ref}
        @module.handle_other(msg, state)
      end)
    end
  end
end
