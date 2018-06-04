defmodule Overmind.MixProject do
  use Mix.Project

  def project do
    [
      app: :overmind,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :libring],
      mod: {Overmind.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:zookeeper, github: "vishnevskiy/zookeeper-elixir"},
      {:libring, "~> 1.0"},

      {:stream_data, "~> 0.4.2", only: :test},
      # test/housekeeping stuff
      {:excoveralls, "~> 0.4", only: :test},
      {:ex_doc, "~> 0.18.1", only: :dev},
      {:mix_test_watch, "~> 0.5", only: :dev, runtime: false},
    ]
  end
end
