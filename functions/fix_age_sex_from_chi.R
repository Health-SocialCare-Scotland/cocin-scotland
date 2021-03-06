sex_from_chi <- function(chi) {
  chi_sex <- dplyr::if_else((stringr::str_sub(chi, 9, 9) %>%
    readr::parse_integer() %>%
    mod(2)) == 0, "Female", "Male") %>%
    factor(levels = c("Male", "Female", "Not specified"))

  return(chi_sex)
}

dob_from_chi <- function(chi) {
  max_age <- 110L

  # Create dates as all DD/MM/19YY
  date1 <- stringr::str_sub(chi, 1, 6) %>%
    lubridate::parse_date_time2("dmy", cutoff_2000 = -1L) %>%
    as_date()
  # Create dates as all DD/MM/20YY
  date2 <- stringr::str_sub(chi, 1, 6) %>%
    lubridate::parse_date_time2("dmy", cutoff_2000 = 100L) %>%
    as_date()

  chi_dob <- dplyr::case_when(
    date2 >= Sys.Date() ~ date1,
    # Not as accurate as lubridate::time_length which does leap years correctly but much faster
    (difftime(Sys.Date(), date1, unit = "days") / 365.25) > max_age ~ date2,
    TRUE ~ NA_Date_
  )

  return(chi_dob)
}

fix_age_sex_from_chi <- function(data) {
  valid_chis <- data %>%
    dplyr::select(subjid, nhs_chi, agedat, age, sex, hostdat, daily_dsstdat, cestdat, dsstdat) %>%
    dplyr::mutate_at(vars(agedat, hostdat, daily_dsstdat, cestdat, dsstdat), as_date) %>%
    dplyr::group_by(subjid) %>%
    dplyr::summarise_all(~ dplyr::coalesce(.)) %>%
    dplyr::filter(phsmethods::chi_check(nhs_chi) == "Valid CHI")

  missing_age <- valid_chis %>% dplyr::filter(is.na(age))
  missing_sex <- valid_chis %>% dplyr::filter(is.na(sex))

  fixed_age <- missing_age %>%
    dplyr::filter(is.na(agedat)) %>%
    dplyr::mutate(
      agedat = dob_from_chi(nhs_chi),

      # Date at which to calculate age
      anydat = dplyr::coalesce(hostdat, daily_dsstdat, cestdat, dsstdat),

      # Calculate age using DOB and anydat derived above
      age = lubridate::interval(agedat, anydat) %>%
        lubridate::as.period() %>%
        lubridate::year() %>%
        as.double()
    ) %>%
    dplyr::select(subjid, agedat, age)

  fixed_sex <- missing_sex %>%
    dplyr::mutate(sex = sex_from_chi(nhs_chi)) %>%
    dplyr::select(subjid, sex)

  fixed_data <- purrr::reduce(list(data, fixed_sex, fixed_age),
    left_join,
    by = "subjid",
    suffix = c("", "_fix")
  ) %>%
    mutate(
      age = dplyr::if_else(is.na(age_fix), age, age_fix),
      agedat = dplyr::if_else(is.na(agedat_fix), agedat, agedat_fix),
      sex = dplyr::if_else(is.na(sex_fix), sex, sex_fix)
    )

  message(stringr::str_glue("Fixed {n_dob} records with missing DoBs and {n_sex} records with missing sex.",
    n_dob = sum(!is.na(fixed_age$agedat)),
    n_sex = sum(!is.na(fixed_sex$sex))
  ))

  return(fixed_data)
}
