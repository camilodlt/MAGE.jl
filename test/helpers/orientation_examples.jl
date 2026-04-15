function orientation_vertical_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    img[:, fld(n, 2)+1:end] .= 1.0
    return img
end

function orientation_horizontal_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    img[fld(n, 2)+1:end, :] .= 1.0
    return img
end

function orientation_horizontal_bars_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for r in 4:8:(n - 3)
        img[r:min(r + 2, n), :] .= 1.0
    end
    return img
end

function orientation_vertical_bars_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for c in 4:8:(n - 3)
        img[:, c:min(c + 2, n)] .= 1.0
    end
    return img
end

function orientation_diag45_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for i in 1:n
        for d in -1:1
            j = i + d
            if 1 <= j <= n
                img[i, j] = 1.0
            end
        end
    end
    return img
end

function orientation_diag135_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for i in 1:n
        for d in -1:1
            j = n - i + 1 + d
            if 1 <= j <= n
                img[i, j] = 1.0
            end
        end
    end
    return img
end

function orientation_diag45_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for i in 1:n, j in 1:n
        img[i, j] = j >= i ? 1.0 : 0.0
    end
    return img
end

function orientation_diag135_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for i in 1:n, j in 1:n
        img[i, j] = j >= (n - i + 1) ? 1.0 : 0.0
    end
    return img
end

function orientation_cross_array(n::Int = 30)
    img = orientation_horizontal_bars_array(n)
    img .+= orientation_vertical_bars_array(n)
    return clamp.(img, 0.0, 1.0)
end

function orientation_intensity_image(arr::AbstractMatrix{<:Real})
    return SImageND(IntensityPixel{N0f8}.(Float64.(arr)))
end
