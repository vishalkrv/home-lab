//#############################//
//                             //
//   Auto Commits Generator    //
//                             //
//#############################//


const { execSync } = require("child_process");
const fs = require("fs");

// Function to format a date and time into YYYY-MM-DDTHH:MM:SS
function formatDateTime(date) {
    return date.toISOString().replace("T", " ").split(".")[0];
}

// Function to generate a random commit message
function generateRandomMessage() {
    const messages = [
        "Fix bug in the module",
        "Add new feature",
        "Refactor codebase",
        "Update documentation",
        "Improve performance",
        "Fix typos",
        "Add tests",
        "Update dependencies",
        "Optimize algorithm",
        "Cleanup code"
    ];
    return messages[Math.floor(Math.random() * messages.length)];
}

// Function to check if a date is a weekend
function isWeekend(date) {
    const day = date.getDay();
    return day === 0 || day === 6; // 0 = Sunday, 6 = Saturday
}

// Function to generate a random time during the day
function generateRandomTime(date) {
    const randomHour = Math.floor(Math.random() * 24);
    const randomMinute = Math.floor(Math.random() * 60);
    const randomSecond = Math.floor(Math.random() * 60);

    // Set the random time to the date object
    date.setHours(randomHour);
    date.setMinutes(randomMinute);
    date.setSeconds(randomSecond);

    return date;
}

// Function to perform a Git commit
function makeCommit(date) {
    const commitDateTime = formatDateTime(date);
    const commitMessage = generateRandomMessage();
    const fileName = "temp_commit_file.txt";

    // Create a temporary file for the commit with unique content
    const fileContent = `Commit on ${commitDateTime}: ${Math.random()}`;
    fs.writeFileSync(fileName, fileContent);

    try {
        // Stage the file, commit, and set commit date
        execSync(`git add ${fileName}`);
        execSync(`git commit -m "${commitMessage}" --date="${commitDateTime}"`, { stdio: "inherit" });
        console.log(`Committed on ${commitDateTime}: ${commitMessage}`);
    } catch (err) {
        console.error("Error during commit:", err.message);
    }

    // Remove the temporary file
    fs.unlinkSync(fileName);
}

// Main function to handle the commit automation
function autoCommit({ startDate, endDate, maxCommitsPerDay, skipWeekends, onlyWeekends }) {
    let currentDate = new Date(startDate);
    const finalDate = new Date(endDate);

    while (currentDate <= finalDate) {
        const isCurrentWeekend = isWeekend(currentDate);

        if ((skipWeekends && isCurrentWeekend) || (onlyWeekends && !isCurrentWeekend)) {
            // Skip the current day if conditions are not met
            currentDate.setDate(currentDate.getDate() + 1);
            continue;
        }

        const commitsToday = Math.floor(Math.random() * maxCommitsPerDay) + 1;

        for (let i = 0; i < commitsToday; i++) {
            const commitDate = generateRandomTime(new Date(currentDate));
            makeCommit(commitDate);
        }

        // Move to the next day
        currentDate.setDate(currentDate.getDate() + 1);
    }
}

// Input: Customize these parameters as needed
const options = {
    startDate: "2025-01-01", // Start date in YYYY-MM-DD
    endDate: "2025-01-10",   // End date in YYYY-MM-DD
    maxCommitsPerDay: 4,     // Maximum commits in a day
    skipWeekends: true,      // Skip weekends
    onlyWeekends: false      // Commit only on weekends
};

// Run the script
autoCommit(options);