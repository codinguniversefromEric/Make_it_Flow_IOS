import subprocess
import PyPDF2

reader = PyPDF2.PdfReader("/Users/giyoshimiken/Documents/testbooks/book 1/Eric-Jorgenson_The-Almanack-of-Naval-Ravikant_Final.pdf")
text = ""
for page in reader.pages:
    text += page.extract_text() + "\n"

print("Count of + :", text.count("+"))
print("Count of - :", text.count("-"))
print("Count of = :", text.count("="))
print("Count of / :", text.count("/"))

