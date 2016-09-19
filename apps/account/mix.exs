defmodule Account.Mixfile do
  use Mix.Project

  alias HELM.Account

  def project do
    [app: :account,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :cowboy, :ecto, :postgrex, :comeonin, :he_broker],
     mod: {Account.App, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:he_broker, git: "ssh://git@git.hackerexperience.com/diffusion/BROKER/HEBroker.git"},
     {:helf, git: "ssh://git@git.hackerexperience.com/diffusion/HELF/helf.git", tag: "v1.1.1"},
     {:postgrex, ">= 0.0.0"},
     {:ecto, "~> 2.0"},
     {:comeonin, "~> 2.5"},
     {:poison, "~> 2.0"}] # TODO: add guardian
  end
end
