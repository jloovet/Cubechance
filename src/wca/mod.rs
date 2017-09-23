extern crate zip;
extern crate reqwest;
extern crate chrono;


pub mod wca_export;
pub mod wca_competitors;

use self::zip::result::ZipError;
use std::num::ParseIntError;
use std::io;
use std::collections::HashMap;
use std::convert::From;
use std::vec::Vec;

use self::chrono::Date;
use self::chrono::offset;


#[derive(Debug)]
pub enum WcaError {
    ZipE(ZipError),
    IoE(io::Error),
    NumE(ParseIntError),
    NetE(reqwest::Error),
    UrlE(reqwest::UrlError),
    ReadE(String),
    PersonE(String),
    CompE(String)
}

impl From<ZipError> for WcaError {
    fn from(e: ZipError) -> WcaError {
        WcaError::ZipE(e)
    }
}
impl From<io::Error> for WcaError {
    fn from(e: io::Error) -> WcaError {
        WcaError::IoE(e)
    }
}
impl From<ParseIntError> for WcaError {
    fn from(e: ParseIntError) -> WcaError {
        WcaError::NumE(e)
    }
}
impl From<reqwest::Error> for WcaError {
    fn from(e: reqwest::Error) -> WcaError {
        WcaError::NetE(e)
    }
}
impl From<reqwest::UrlError> for WcaError {
    fn from(e: reqwest::UrlError) -> WcaError {
        WcaError::UrlE(e)
    }
}


#[derive(Debug, Default)]
pub struct WcaResults {
    pub people: HashMap<String, WcaPerson>, // Id: Person
    pub comps: Vec<Competition>,
}

#[derive(Debug, Default)]
pub struct WcaPerson {
    pub name: String,
    pub times: HashMap<String, Vec<Time>> // Event: [times]
}

#[derive(Debug)]
pub struct Competition {
    pub name: String,
    pub id: String,
    pub competitors: Vec<Competitor>,
    pub start: Date<offset::Utc>,
    pub end: Date<offset::Utc>,
}

#[derive(Debug, Default)]
pub struct Competitor {
    pub id: String,
    pub events: Vec<String>
}

#[derive(Debug)]
pub enum Time {
    DNF,
    Time(u16)
}

impl Default for Time {
    fn default() -> Time { Time::DNF }
}
