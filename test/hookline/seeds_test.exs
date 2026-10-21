defmodule Hookline.SeedsTest do
  use Hookline.DataCase, async: false

  import ExUnit.CaptureIO

  alias Hookline.Relay.{DeliveryAttempt, Endpoint, Event}
  alias Hookline.Repo

  @seeds_path Path.expand("../../priv/repo/seeds.exs", __DIR__)

  test "seeding twice leaves the database exactly as seeding once did" do
    capture_io(fn -> Code.eval_file(@seeds_path) end)

    endpoints_after_first = Repo.aggregate(Endpoint, :count)
    events_after_first = Repo.aggregate(Event, :count)
    attempts_after_first = Repo.aggregate(DeliveryAttempt, :count)

    assert endpoints_after_first == 2
    assert events_after_first == 5
    assert attempts_after_first == 5

    capture_io(fn -> Code.eval_file(@seeds_path) end)

    assert Repo.aggregate(Endpoint, :count) == endpoints_after_first
    assert Repo.aggregate(Event, :count) == events_after_first
    assert Repo.aggregate(DeliveryAttempt, :count) == attempts_after_first
  end
end
