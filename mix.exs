defmodule Overmind.MixProject do
  use Mix.Project

  def project() do
    [
      app: :overmind,
      version: "0.1.0",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      elixirc_options: [
        warnings_as_errors: true
      ],
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application() do
    [
      extra_applications: [:logger, :libring, :erlzk],
      mod: {Overmind.Application, []}
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]

  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/nietaki/overmind",
      extras: ["README.md"],
      assets: ["assets"]
      # logo: "assets/todo.png",
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps() do
    [
      {:erlzk, "~> 0.6.4"},
      {:libring, "~> 1.0"},
      {:gen_state_machine, "~> 2.0"},
      {:stream_data, "~> 0.4.2", only: :test},

      # test/housekeeping stuff
      {:excoveralls, "~> 0.4", only: :test},
      {:ex_doc, "~> 0.18.1", only: :dev},
      {:mix_test_watch, "~> 0.5", only: :dev, runtime: false}
    ]
  end
end
