defmodule HooklineWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use HooklineWeb, :controller` and
  `use HooklineWeb, :live_view`.
  """
  use HooklineWeb, :html

  embed_templates "layouts/*"
end
