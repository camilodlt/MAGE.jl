
"""
Text from paper: 

Given an integer representing a number
of hours and 3 ﬂoats representing how much snow is on the
ground, the rate of snow fall, and the proportion of snow
melting per hour, return the amount of snow on the ground
after the amount of hours given. Each hour is considered a
discrete event of adding snow and then melting, not a con-
tinuous process.
"""

train_data = []

function snow_day_algo(x, y)
    n_hours = x[1]
    n_snow = x[2]
    rate_snow = x[3]
    melt_prop_per_hour = x[4]

    # Calc how much snow is added 
    more_snow = number_mult(rate_snow, n_hours)

    # Calc how much snow is melted 
    less_snow = number_mult(melt_prop_per_hour, n_hour)

    # delta 
    d = number_sum(more_snow, less_snow)

    # Add 
    res = number_sum(n_snow, d)
    res == y[1]
end

@testset "Snow Day" begin
    for (x, y) in train_data
        @test begin
            snow_day_algo(x, y)
        end
    end
end

