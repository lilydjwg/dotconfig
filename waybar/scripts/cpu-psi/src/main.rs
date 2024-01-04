#![feature(thread_sleep_until)]

use std::fs;
use std::io::{self, BufRead, Write};
use std::thread::sleep_until;
use std::time::{Instant, Duration};
use std::fmt;

fn get_load() -> f32 {
  let load_string = fs::read_to_string("/proc/loadavg").unwrap();
  let mut split = load_string.split(' ');
  let load1 = split.next().unwrap();
  load1.parse().unwrap()
}

struct CpuInfo {
  idle: u64,
  total: u64,
}

fn get_cpu_time() -> CpuInfo {
  let f = fs::File::open("/proc/stat").unwrap();
  let mut f = io::BufReader::new(f);
  let mut line = String::new();
  f.read_line(&mut line).unwrap();
  let numbers: Vec<u64> = line.split_ascii_whitespace().skip(1) // cpu
    .map(|i| i.parse().unwrap())
    .collect();
  CpuInfo {
    idle: numbers[3] + numbers[4],
    total: numbers.iter().sum(),
  }
}

fn get_psi(which: &str) -> f32 {
  let f = fs::File::open(format!("/proc/pressure/{which}")).unwrap();
  let mut f = io::BufReader::new(f);
  let mut line = String::new();
  f.read_line(&mut line).unwrap();
  line.split(' ').nth(1).unwrap().split('=').nth(1).unwrap().parse().unwrap()
}

struct Colored<T> {
  value: T,
  orange: T,
  red: T,
}

impl<T: PartialOrd + fmt::Display> fmt::Display for Colored<T> {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    let w = f.width().unwrap_or(0);
    let p = f.precision().unwrap_or(0);
    if self.value > self.red {
      write!(f, r##"<span color="#ff0000">{:w$.p$}</span>"##, self.value)
    } else if self.value > self.orange {
      write!(f, r##"<span color="#ffa500">{:w$.p$}</span>"##, self.value)
    } else {
      write!(f, r##"{:w$.p$}"##, self.value)
    }
  }
}

fn main() {
  let mut old_cpuinfo = get_cpu_time();
  let one_second = Duration::from_secs(1);
  let mut next_time = Instant::now() + one_second;
  let cpu_count = num_cpus::get() as f32;
  let mut stdout = io::stdout().lock();
  loop {
    sleep_until(next_time);

    let cpuinfo = get_cpu_time();
    let load = get_load();
    let psi_cpu = get_psi("cpu");
    let psi_mem = get_psi("memory");
    let psi_io = get_psi("io");

    let text = format!(
      "CPU{cpu:4}% Load{load:5.2} C{psi_cpu:4.1} M{psi_mem:4.1} D{psi_io:4.1}",
      cpu = Colored {
        value: (1.0 - (cpuinfo.idle - old_cpuinfo.idle) as f32
          / (cpuinfo.total - old_cpuinfo.total) as f32) * cpu_count * 100.0,
        orange: 60.0 * cpu_count,
        red: 90.0 * cpu_count,
      },
      load = Colored { value: load, orange: 0.5 * cpu_count, red: 0.9 * cpu_count },
      psi_cpu = Colored { value: psi_cpu, orange: 1.0, red: 5.0 },
      psi_mem = Colored { value: psi_mem, orange: 1.0, red: 5.0 },
      psi_io = Colored { value: psi_io, orange: 20.0, red: 90.0 },
    );
    let output = format!(
      "{{\"text\": \"{}\", \"tooltip\": \"\", \"class\": \"\", \"percentage\": 0 }}\n",
      text.replace('"', r#"\""#),
    );
    stdout.write_all(output.as_bytes()).unwrap();
    stdout.flush().unwrap();

    next_time += one_second;
    old_cpuinfo = cpuinfo;
  }
}
