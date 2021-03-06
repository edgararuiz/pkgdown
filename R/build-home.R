#' Build home page
#'
#' First looks for \code{index.Rmd} or \code{README.Rmd}, then
#' \code{index.md} or \code{README.md}. If none are found, falls back to the
#' description field in \code{DESCRIPTION}.
#'
#' @section YAML config:
#' To tweak the home page, you need a section called \code{home}.
#'
#' The sidebar links are automatically generated by inspecting the
#' \code{URL} and \code{BugReports} fields of the \code{DESCRIPTION}.
#' You can add additional links with a subsection called \code{links},
#' which should contain a list of \code{text} + \code{href} elements:
#'
#' \preformatted{
#' home:
#'   links:
#'   - text: Link text
#'     href: http://website.com
#' }
#'
#' The "developers" list is populated by the maintainer ("cre"), authors
#' ("aut"), and funder ("fnd").
#'
#' @inheritParams build_articles
#' @export
build_home <- function(pkg = ".", path = "docs", depth = 0L, encoding = "UTF-8") {
  old <- set_pkgdown_env("true")
  on.exit(set_pkgdown_env(old))

  rule("Building home")

  pkg <- as_pkgdown(pkg)
  path <- rel_path(path, pkg$path)
  data <- data_home(pkg)

  # Copy license file, if present
  license_path <- file.path(pkg$path, "LICENSE")
  if (file.exists(license_path)) {
    file.copy(license_path, path)
  }

  # Build authors page
  build_authors(pkg, path = path, depth = depth)

  if (is.null(data$path)) {
    data$index <- pkg$desc$get("Description")[[1]]
    render_page(pkg, "home", data, out_path(path, "index.html"), depth = depth)
  } else {
    file_name <- tools::file_path_sans_ext(basename(data$path))
    file_ext <- tools::file_ext(data$path)

    if (file_ext == "md") {
      data$index <- markdown(path = data$path, depth = 0L, index = pkg$topics)
      render_page(pkg, "home", data, out_path(path, "index.html"), depth = depth)
    } else if (file_ext == "Rmd") {
      if (identical(file_name, "README")) {
        # Render once so that .md is up to date
        message("Updating ", file_name, ".md")
        callr::r_safe(
          function(input, encoding) {
            rmarkdown::render(
              input,
              output_options = list(html_preview = FALSE),
              quiet = TRUE,
              encoding = encoding
            )
          },
          args = list(
            input = data$path,
            encoding = encoding
          )
        )
      }

      input <- file.path(path, basename(data$path))
      file.copy(data$path, input)
      on.exit(unlink(input))

      render_rmd(pkg, input, "index.html",
        depth = depth,
        data = data,
        toc = FALSE,
        strip_header = TRUE,
        encoding = encoding
      )
    }
  }

  update_homepage_html(
    out_path(path, "index.html"),
    isTRUE(pkg$meta$home$strip_header)
  )

  invisible()
}

tweak_homepage_html <- function(html, strip_header = FALSE) {
  first_para <- xml2::xml_find_first(html, "//p")
  badges <- first_para %>% xml2::xml_children()
  has_badges <- length(badges) > 0 && all(xml2::xml_name(badges) %in% "a")

  if (has_badges) {
    list <- list_with_heading(badges, "Dev status")
    list_div <- paste0("<div>", list, "</div>")
    list_html <- list_div %>% xml2::read_html() %>% xml2::xml_find_first(".//div")

    html %>%
      xml2::xml_find_first(".//div[@id='sidebar']") %>%
      xml2::xml_add_child(list_html)

    xml2::xml_remove(first_para)
  }

  header <- xml2::xml_find_first(html, ".//h1")
  if (strip_header) {
    xml2::xml_remove(header, free = TRUE)
  } else {
    page_header_text <- paste0("<div class='page-header'>", header, "</div>")
    page_header <- xml2::read_html(page_header_text) %>% xml2::xml_find_first("//div")
    xml2::xml_replace(header, page_header)
  }

  # Fix relative image links
  imgs <- xml2::xml_find_all(html, ".//img")
  urls <- xml2::xml_attr(imgs, "src")
  new_urls <- gsub("^vignettes/", "articles/", urls)
  new_urls <- gsub("^man/figures/", "reference/figures/", new_urls)
  purrr::map2(imgs, new_urls, ~ (xml2::xml_attr(.x, "src") <- .y))

  tweak_tables(html)

  invisible()
}

update_homepage_html <- function(path, strip_header = FALSE) {
  html <- xml2::read_html(path, encoding = "UTF-8")
  tweak_homepage_html(html, strip_header = strip_header)

  xml2::write_html(html, path, format = FALSE)
  path
}

data_home <- function(pkg = ".") {
  pkg <- as_pkgdown(pkg)

  path <- find_first_existing(pkg$path,
    c("index.Rmd", "README.Rmd", "index.md", "README.md")
  )

  print_yaml(list(
    pagetitle = pkg$desc$get("Title")[[1]],
    sidebar = data_home_sidebar(pkg),
    path = path
  ))
}

data_home_sidebar <- function(pkg = ".") {
  if (!is.null(pkg$meta$home$sidebar))
    return(pkg$meta$home$sidebar)

  paste0(
    data_home_sidebar_links(pkg),
    data_home_sidebar_license(pkg),
    data_home_sidebar_authors(pkg),
    collapse = "\n"
  )
}

data_home_sidebar_license <- function(pkg = ".") {
  pkg <- as_pkgdown(pkg)

  paste0(
    "<h2>License</h2>\n",
    "<p>", autolink_license(pkg$desc$get("License")[[1]]), "</p>\n"
  )
}

data_home_sidebar_links <- function(pkg = ".") {
  pkg <- as_pkgdown(pkg)

  links <- c(
    data_link_cran(pkg),
    data_link_github(pkg),
    data_link_bug_report(pkg),
    data_link_meta(pkg)
  )

  list_with_heading(links, "Links")
}

list_with_heading <- function(bullets, heading) {
  if (length(bullets) == 0)
    return(character())

  paste0(
    "<h2>", heading, "</h2>",
    "<ul class='list-unstyled'>\n",
    paste0("<li>", bullets, "</li>\n", collapse = ""),
    "</ul>\n"
  )
}

data_link_meta <- function(pkg = ".") {
  pkg <- as_pkgdown(pkg)
  links <- pkg$meta$home$links

  if (length(links) == 0)
    return(character())

  links %>%
    purrr::transpose() %>%
    purrr::pmap_chr(link_url)
}

data_link_github <- function(pkg = ".") {
  pkg <- as_pkgdown(pkg)

  urls <- pkg$desc$get("URL") %>%
    strsplit(",\\s+") %>%
    `[[`(1)

  github <- grepl("github", urls)

  if (!any(github))
    return(character())

  link_url("Browse source code", urls[which(github)[[1]]])
}

data_link_bug_report <- function(pkg = ".") {
  pkg <- as_pkgdown(pkg)

  bug_reports <- pkg$desc$get("BugReports")[[1]]

  if (is.na(bug_reports))
    return(character())

  link_url("Report a bug", bug_reports)
}

data_link_cran <- function(pkg = ".") {
  pkg <- as_pkgdown(pkg)

  name <- pkg$desc$get("Package")[[1]]
  if (!on_cran(name))
    return(list())

  link_url(
    "Download from CRAN",
    paste0("https://cran.r-project.org/package=", name)
  )
}


cran_mirror <- function() {
  cran <- as.list(getOption("repos"))[["CRAN"]]
  if (is.null(cran) || identical(cran, "@CRAN@")) {
    "https://cran.rstudio.com"
  } else {
    cran
  }
}
on_cran <- function(pkg, cran = cran_mirror()) {
  pkgs <- utils::available.packages(
    type = "source",
    contriburl = paste0(cran, "/src/contrib"))
  pkg %in% rownames(pkgs)
}


link_url <- function(text, href) {
  label <- gsub("(/+)", "\\1&#8203;", href)
  paste0(text, " at <br /><a href='", href, "'>", label, "</a>")
}
