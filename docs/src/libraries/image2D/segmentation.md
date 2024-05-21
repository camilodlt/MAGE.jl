```@meta
CurrentModule = UTCGP
DocTestSetup = quote
  using ImageCore:N0f8
  using UTCGP:SImageND
  using UTCGP.image2D_segmentation:felzenswalb_image2D_factory
end
```

```@contents
Pages = ["segmentation.md"]
```

# Segmentation Algorithms

### Module

```@docs
UTCGP.image2D_segmentation
```

### Algorithms

```@docs
UTCGP.image2D_segmentation.felzenswalb_image2D_factory
```

```@example
img = SImageND(ones(N0f8,10,10))
dp = felzenswalb_image2D_factory(typeof(img))
```

```@meta
DocTestSetup = quote
  using ImageCore:N0f8
  using UTCGP:SImageND
  using UTCGP.image2D_segmentation:felzenswalb_image2D_factory
end
```

```@example
using ImageCore
# 2 instances (1,0s) 
image = ones(N0f8,10,10)
image[2:4,2:4] .= 0
img = SImageND(image)
dp = felzenswalb_image2D_factory(typeof(img))
res = dp(img, 10)
print(res)
```
