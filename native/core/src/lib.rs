//! Offline simulation kernel. No renderer, assets, threads or network dependencies.
pub const ABI_VERSION: i32 = 1;

/// Versioned flat interface, mirrored by NativeSimulation in Godot.
/// Invalid/non-finite input is rejected rather than poisoning a saved session.
pub fn physics(a: &[f64]) -> Option<[f64; 6]> {
    if a.len() != 19 || a.iter().any(|v| !v.is_finite()) || a[9] <= 0.0 {
        return None;
    }
    if a[10..16].iter().any(|v| *v < 0.0) || !(0.0..=1.0).contains(&a[16]) {
        return None;
    }
    let (mut velocity, mut position, mut slip, mut time) = (a[0], a[1], a[2], a[3]);
    let (dt, notch, grade, emergency, power, m) = (a[4], a[5], a[6], a[7] > 0.0, a[8] > 0.0, a[9]);
    if dt <= 0.0 {
        return Some([velocity, position, slip, time, 0.0, 0.0]);
    }
    let speed = velocity.abs();
    let demand = if notch > 0.0 && power && !emergency {
        notch.clamp(0.0, 1.0) * a[10].min(a[11] * 1000.0 / speed.max(1.0))
    } else {
        0.0
    };
    let mu = if a[18] > 0.0 {
        a[15].max(0.55)
    } else {
        if a[17] > 0.0 {
            (a[15] + 0.08).min(0.30)
        } else {
            a[15]
        }
        .max(0.02)
    };
    let grip = mu * m * 9.80665 * a[16];
    let wheel_slip = demand > grip * 1.02;
    time += dt;
    let target = if wheel_slip {
        ((demand - grip) / grip.max(1.0)).clamp(0.0, 1.0)
    } else {
        0.0
    };
    slip += (target - slip).clamp(-dt * 3.0, dt * 3.0);
    let traction = if wheel_slip {
        demand.min(grip * (0.90 + 0.04 * (time * 19.0).sin()))
    } else {
        demand
    };
    let mut brake = if emergency {
        a[13] * m
    } else {
        (-notch).max(0.0) * a[12] * m
    };
    let wheel_slide = !emergency && speed > 0.3 && brake > mu * m * 9.80665 * 1.02;
    if wheel_slide {
        brake = mu * m * 9.80665 * 0.85;
    }
    let drive = traction - m * 9.80665 * grade;
    let drag = 0.0015 * m * 9.80665 + 0.05 * m * 0.01 * speed + 6.0 * speed * speed;
    if speed < 0.015 && drive.abs() <= brake + drag {
        velocity = 0.0;
    } else {
        let sign = if speed < 0.015 {
            drive.signum()
        } else {
            velocity.signum()
        };
        let mut next = velocity + (drive - sign * (brake + drag)) / m * dt;
        if next * velocity < 0.0 && drive.abs() <= brake + drag {
            next = 0.0;
        }
        velocity = next.clamp(-a[14], a[14]);
        position += velocity * dt;
    }
    Some([
        velocity,
        position,
        slip,
        time,
        if wheel_slip { 1.0 } else { 0.0 },
        if wheel_slide { 1.0 } else { 0.0 },
    ])
}

/// Exponential transitions; rainfall and rail wetness deliberately have different time constants.
pub fn weather(a: &[f64]) -> Option<[f64; 4]> {
    if a.len() != 8 || a.iter().any(|v| !v.is_finite()) || a[7] < 0.0 {
        return None;
    }
    let blend = 1.0 - (-a[7] / a[6].max(0.1)).exp();
    let rain = a[0] + (a[3].clamp(0.0, 1.0) - a[0]) * blend;
    let fog = a[1] + (a[4].clamp(0.0, 1.0) - a[1]) * blend;
    let wet = a[2] + (rain - a[2]) * (1.0 - (-a[7] / if rain > a[2] { 20.0 } else { 180.0 }).exp());
    Some([rain, fog, wet, 0.26 + (0.12 - 0.26) * wet.clamp(0.0, 1.0)])
}

#[cfg(test)]
mod tests {
    use super::*;
    fn input() -> [f64; 19] {
        [
            0.0,
            0.0,
            0.0,
            0.0,
            1.0 / 60.0,
            0.0,
            0.0,
            0.0,
            1.0,
            41000.0,
            110000.0,
            720.0,
            1.2,
            2.8,
            70.0 / 3.6,
            0.26,
            0.55,
            0.0,
            0.0,
        ]
    }
    #[test]
    fn f3_holds_slope_but_neutral_rolls_back() {
        let mut a = input();
        a[6] = 0.05;
        a[5] = -0.75;
        assert_eq!(physics(&a).unwrap()[0], 0.0);
        a[5] = 0.0;
        assert!(physics(&a).unwrap()[0] < 0.0);
    }
    #[test]
    fn no_power_no_traction() {
        let mut a = input();
        a[5] = 1.0;
        a[8] = 0.0;
        assert_eq!(physics(&a).unwrap()[0], 0.0);
    }
    #[test]
    fn wet_rail_slips_and_sand_recovers_grip() {
        let mut a = input();
        a[5] = 1.0;
        a[15] = 0.07;
        let x = physics(&a).unwrap();
        a[17] = 1.0;
        let y = physics(&a).unwrap();
        assert_eq!(x[4], 1.0);
        assert!(y[0] > x[0]);
    }
    #[test]
    fn emergency_stops_without_reversing() {
        let mut a = input();
        a[0] = 0.02;
        a[7] = 1.0;
        assert_eq!(physics(&a).unwrap()[0], 0.0);
    }
    #[test]
    fn invalid_data_is_rejected() {
        let mut a = input();
        a[0] = f64::NAN;
        assert!(physics(&a).is_none());
        assert!(weather(&[]).is_none());
    }
    #[test]
    fn wetness_persists() {
        let x = weather(&[1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 5.0]).unwrap();
        assert!(x[0] < 0.01);
        assert!(x[2] > 0.95);
        assert!(x[3] < 0.14);
    }
}
