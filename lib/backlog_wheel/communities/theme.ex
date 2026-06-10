defmodule BacklogWheel.Communities.Theme do
  @moduledoc false

  @color_fields [
    :light_primary_color,
    :light_accent_color,
    :light_background_color,
    :dark_primary_color,
    :dark_accent_color,
    :dark_background_color
  ]

  @defaults %{
    light: %{
      primary: "#f97316",
      accent: "#c026d3",
      background: "#fafafa"
    },
    dark: %{
      primary: "#f97316",
      accent: "#a855f7",
      background: "#1f2937"
    }
  }

  def color_fields, do: @color_fields

  def defaults, do: @defaults

  def resolve(community) do
    light = explicit_theme(community, :light)
    dark = explicit_theme(community, :dark)

    resolved_light = %{
      primary: light.primary || derive_or_default(dark.primary, :light, :primary),
      accent: light.accent || derive_or_default(dark.accent, :light, :accent),
      background: light.background || derive_or_default(dark.background, :light, :background)
    }

    resolved_dark = %{
      primary: dark.primary || derive_or_default(light.primary, :dark, :primary),
      accent: dark.accent || derive_or_default(light.accent, :dark, :accent),
      background: dark.background || derive_or_default(light.background, :dark, :background)
    }

    %{
      light: add_content_colors(resolved_light),
      dark: add_content_colors(resolved_dark)
    }
  end

  def style(theme) do
    [
      css_var("theme-light-primary", theme.light.primary),
      css_var("theme-light-primary-content", theme.light.primary_content),
      css_var("theme-light-accent", theme.light.accent),
      css_var("theme-light-accent-content", theme.light.accent_content),
      css_var("theme-light-background", theme.light.background),
      css_var("theme-light-background-content", theme.light.background_content),
      css_var("theme-light-base-200", shade(theme.light.background, :light, 0.04)),
      css_var("theme-light-base-300", shade(theme.light.background, :light, 0.08)),
      css_var("theme-dark-primary", theme.dark.primary),
      css_var("theme-dark-primary-content", theme.dark.primary_content),
      css_var("theme-dark-accent", theme.dark.accent),
      css_var("theme-dark-accent-content", theme.dark.accent_content),
      css_var("theme-dark-background", theme.dark.background),
      css_var("theme-dark-background-content", theme.dark.background_content),
      css_var("theme-dark-base-200", shade(theme.dark.background, :dark, 0.06)),
      css_var("theme-dark-base-300", shade(theme.dark.background, :dark, 0.12))
    ]
    |> Enum.join(" ")
  end

  defp explicit_theme(community, mode) do
    %{
      primary: Map.get(community, field(mode, :primary_color)),
      accent: Map.get(community, field(mode, :accent_color)),
      background: Map.get(community, field(mode, :background_color))
    }
  end

  defp field(:light, :primary_color), do: :light_primary_color
  defp field(:light, :accent_color), do: :light_accent_color
  defp field(:light, :background_color), do: :light_background_color
  defp field(:dark, :primary_color), do: :dark_primary_color
  defp field(:dark, :accent_color), do: :dark_accent_color
  defp field(:dark, :background_color), do: :dark_background_color

  defp derive_or_default(nil, mode, key), do: @defaults[mode][key]

  defp derive_or_default(color, mode, key) do
    color
    |> parse_hex!()
    |> rgb_to_hsl()
    |> derive_hsl(mode, key)
    |> hsl_to_rgb()
    |> format_hex()
  end

  defp derive_hsl({h, s, l}, :dark, :background), do: {h, s * 0.7, clamp(1 - l, 0.12, 0.22)}
  defp derive_hsl({h, s, l}, :light, :background), do: {h, s * 0.45, clamp(1 - l, 0.94, 0.99)}
  defp derive_hsl({h, s, l}, :dark, _key), do: {h, s, clamp(1 - l, 0.56, 0.72)}
  defp derive_hsl({h, s, l}, :light, _key), do: {h, s, clamp(1 - l, 0.42, 0.64)}

  defp add_content_colors(theme) do
    theme
    |> Map.put(:primary_content, content_color(theme.primary))
    |> Map.put(:accent_content, content_color(theme.accent))
    |> Map.put(:background_content, content_color(theme.background))
  end

  defp content_color(color) do
    {r, g, b} = parse_hex!(color)

    if relative_luminance(r, g, b) > 0.52 do
      "#111827"
    else
      "#f9fafb"
    end
  end

  defp shade(color, :light, amount) do
    color
    |> parse_hex!()
    |> rgb_to_hsl()
    |> then(fn {h, s, l} -> {h, s, clamp(l - amount, 0, 1)} end)
    |> hsl_to_rgb()
    |> format_hex()
  end

  defp shade(color, :dark, amount) do
    color
    |> parse_hex!()
    |> rgb_to_hsl()
    |> then(fn {h, s, l} -> {h, s, clamp(l - amount, 0, 1)} end)
    |> hsl_to_rgb()
    |> format_hex()
  end

  defp css_var(name, value), do: "--#{name}: #{value};"

  defp parse_hex!("#" <> hex) when byte_size(hex) == 3 do
    [r, g, b] = String.graphemes(hex)
    parse_hex!("##{r}#{r}#{g}#{g}#{b}#{b}")
  end

  defp parse_hex!("#" <> hex) when byte_size(hex) == 6 do
    <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end

  defp rgb_to_hsl({r, g, b}) do
    r = r / 255
    g = g / 255
    b = b / 255
    max = Enum.max([r, g, b])
    min = Enum.min([r, g, b])
    l = (max + min) / 2

    if max == min do
      {0, 0, l}
    else
      delta = max - min
      s = if l > 0.5, do: delta / (2 - max - min), else: delta / (max + min)

      h =
        cond do
          max == r -> (g - b) / delta + if(g < b, do: 6, else: 0)
          max == g -> (b - r) / delta + 2
          true -> (r - g) / delta + 4
        end / 6

      {h, s, l}
    end
  end

  defp hsl_to_rgb({_h, 0, l}) do
    value = round(l * 255)
    {value, value, value}
  end

  defp hsl_to_rgb({h, s, l}) do
    q = if l < 0.5, do: l * (1 + s), else: l + s - l * s
    p = 2 * l - q

    {
      hue_to_rgb(p, q, h + 1 / 3),
      hue_to_rgb(p, q, h),
      hue_to_rgb(p, q, h - 1 / 3)
    }
  end

  defp hue_to_rgb(p, q, t) do
    t =
      cond do
        t < 0 -> t + 1
        t > 1 -> t - 1
        true -> t
      end

    value =
      cond do
        t < 1 / 6 -> p + (q - p) * 6 * t
        t < 1 / 2 -> q
        t < 2 / 3 -> p + (q - p) * (2 / 3 - t) * 6
        true -> p
      end

    round(value * 255)
  end

  defp format_hex({r, g, b}), do: "#" <> hex(r) <> hex(g) <> hex(b)

  defp hex(value) do
    value
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
  end

  defp relative_luminance(r, g, b) do
    [r, g, b]
    |> Enum.map(&linear_channel/1)
    |> then(fn [r, g, b] -> 0.2126 * r + 0.7152 * g + 0.0722 * b end)
  end

  defp linear_channel(value) do
    value = value / 255

    if value <= 0.03928 do
      value / 12.92
    else
      :math.pow((value + 0.055) / 1.055, 2.4)
    end
  end

  defp clamp(value, min, max), do: value |> Kernel.max(min) |> Kernel.min(max)
end
