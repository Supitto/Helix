defmodule HELM.Hardware.Mixfile do
  use Mix.Project

  def project do
    [
      app: :hardware,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps]
  end

  def application do
    [
      applications: applications(Mix.env),
      mod: {HELM.Hardware.App, []}]
  end

  defp applications(_),
    do: [:logger, :helf_broker, :ecto, :postgrex, :account, :entity]

  defp deps do
    [
      {:helf_broker, in_umbrella: true},
      {:hell, in_umbrella: true},
      {:account, in_umbrella: true},
      {:entity, in_umbrella: true},
      {:postgrex, ">= 0.0.0"},
      {:ecto, "~> 2.0"},
      {:ecto_network, "~> 0.4.0"}]
  end
end