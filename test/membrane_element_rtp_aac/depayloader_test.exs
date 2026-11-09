defmodule Membrane.RTP.AAC.Depayloader.Test do
  @moduledoc false

  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  describe "depayloader" do
    defp get_pipeline_spec(mode, payload) do
      child(:source, %Membrane.Testing.Source{
        output: payload,
        stream_format: %Membrane.RTP{}
      })
      |> child(:depayloader, %Membrane.RTP.AAC.Depayloader{mode: mode})
      |> child(:sink, Membrane.Testing.Sink)
    end

    # Malformed packets come from a remote peer, so the depayloader must drop them
    # instead of crashing the pipeline
    defp run_test_dropped_packet(packet) do
      mode = :lbr

      {:ok, _supervisor_pid, pipeline_pid} =
        Membrane.Testing.Pipeline.start(spec: get_pipeline_spec(mode, [packet]))

      assert_sink_playing(pipeline_pid, :sink)
      pipeline_ref = Process.monitor(pipeline_pid)

      assert_end_of_stream(pipeline_pid, :sink)
      refute_sink_buffer(pipeline_pid, :sink, _buffer, 0)
      refute_received {:DOWN, ^pipeline_ref, :process, ^pipeline_pid, _reason}

      Membrane.Pipeline.terminate(pipeline_pid)
    end

    defp run_test_inconsistent_sizes(frame, invalid_frame_size) do
      header = <<invalid_frame_size::6, 0::2>>
      packet = <<bit_size(header)::16, header::binary, frame::binary>>
      run_test_dropped_packet(packet)
    end

    defp run_test_invalid_headers_length(frame, invalid_headers_length) do
      header = <<bit_size(frame)::6, 0::2>>
      packet = <<invalid_headers_length::16, header::binary, frame::binary>>
      run_test_dropped_packet(packet)
    end

    test "when sending single packet with invalid frame size" do
      frame = <<1::8, 2::8>>
      run_test_inconsistent_sizes(frame, 0)
      run_test_inconsistent_sizes(frame, 1)
      run_test_inconsistent_sizes(frame, 55)
      run_test_inconsistent_sizes(frame, -2)
    end

    test "when sending single packet with invalid header length" do
      frame = <<1::8, 2::8>>
      run_test_invalid_headers_length(frame, -2)
      run_test_invalid_headers_length(frame, 0)
      run_test_invalid_headers_length(frame, 4)
      run_test_invalid_headers_length(frame, 12)
      run_test_invalid_headers_length(frame, 1000)
    end

    test "when sending a truncated packet" do
      run_test_dropped_packet(<<>>)
      run_test_dropped_packet(<<0>>)
    end
  end
end
