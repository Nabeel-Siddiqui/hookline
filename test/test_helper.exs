ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Hookline.Repo, :manual)
Mox.defmock(Hookline.Relay.HttpClientMock, for: Hookline.Relay.HttpClient)
